package com.redhat.workshop.people.notification;

import com.fasterxml.jackson.annotation.JsonInclude;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record NotificationPayload(
        String title,
        String description,
        String link,
        String severity,
        String topic) {
}
