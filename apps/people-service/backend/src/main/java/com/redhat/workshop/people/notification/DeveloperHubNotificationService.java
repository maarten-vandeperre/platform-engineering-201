package com.redhat.workshop.people.notification;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.redhat.workshop.people.dto.PersonResponse;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

@ApplicationScoped
public class DeveloperHubNotificationService {

    private static final Logger LOG = Logger.getLogger(DeveloperHubNotificationService.class);
    private static final int CONNECT_TIMEOUT_MS = 5_000;
    private static final int READ_TIMEOUT_MS = 10_000;

    @Inject
    ObjectMapper objectMapper;

    @ConfigProperty(name = "developer-hub.notifications.enabled", defaultValue = "false")
    boolean enabled;

    @ConfigProperty(name = "developer-hub.notifications.url")
    Optional<String> notificationsUrl;

    @ConfigProperty(name = "developer-hub.notifications.token")
    Optional<String> notificationsToken;

    @ConfigProperty(name = "developer-hub.notifications.frontend-url")
    Optional<String> developerHubFrontendUrl;

    @ConfigProperty(name = "developer-hub.notifications.recipients", defaultValue = "broadcast")
    String recipientsMode;

    @ConfigProperty(name = "developer-hub.notifications.entity-ref", defaultValue = "user:default/devhub")
    String entityRef;

    public void notifyPersonCreated(PersonResponse person) {
        sendAsync(
                "New person created",
                String.format(
                        "%s %s (age %d) was created via the People REST API.",
                        person.firstName(), person.lastName(), person.age()),
                person);
    }

    public void notifyPersonUpdated(PersonResponse person) {
        sendAsync(
                "Person updated",
                String.format(
                        "%s %s (age %d) was updated via the People REST API.",
                        person.firstName(), person.lastName(), person.age()),
                person);
    }

    public void notifyPersonDeleted(PersonResponse person) {
        sendAsync(
                "Person deleted",
                String.format(
                        "%s %s (id %d) was deleted via the People REST API.",
                        person.firstName(), person.lastName(), person.id()),
                person);
    }

    private void sendAsync(String title, String description, PersonResponse person) {
        if (!enabled) {
            return;
        }
        if (notificationsUrl.isEmpty() || notificationsToken.isEmpty()) {
            LOG.debug("Developer Hub notifications enabled but URL or token is not configured");
            return;
        }

        CompletableFuture.runAsync(() -> sendNotification(title, description, person));
    }

    private void sendNotification(String title, String description, PersonResponse person) {
        try {
            NotificationRecipients recipients = "entity".equalsIgnoreCase(recipientsMode)
                    ? NotificationRecipients.entity(entityRef)
                    : NotificationRecipients.broadcast();

            String link = developerHubFrontendUrl
                    .map(url -> url + "/catalog/default/component/people-service")
                    .orElse(null);

            NotificationPayload payload = new NotificationPayload(
                    title,
                    description,
                    link,
                    "normal",
                    "people-service");

            NotificationRequest request = new NotificationRequest(recipients, payload);
            String body = objectMapper.writeValueAsString(request);

            HttpURLConnection connection =
                    (HttpURLConnection) URI.create(notificationsUrl.get()).toURL().openConnection();
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setRequestProperty("Authorization", "Bearer " + notificationsToken.get());

            try (OutputStream outputStream = connection.getOutputStream()) {
                outputStream.write(body.getBytes(StandardCharsets.UTF_8));
            }

            int statusCode = connection.getResponseCode();
            String responseBody = readResponseBody(connection);

            if (statusCode >= 300) {
                LOG.warnf(
                        "Developer Hub notification failed with HTTP %d: %s",
                        statusCode,
                        responseBody);
            } else {
                LOG.infof("Developer Hub notification sent for person id=%d: %s", person.id(), title);
            }
        } catch (Exception ex) {
            LOG.warnf(ex, "Failed to send Developer Hub notification for person id=%d", person.id());
        }
    }

    private static String readResponseBody(HttpURLConnection connection) throws IOException {
        InputStream stream = connection.getErrorStream();
        if (stream == null) {
            stream = connection.getInputStream();
        }
        if (stream == null) {
            return "";
        }
        return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
    }
}
