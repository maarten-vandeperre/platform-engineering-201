package com.redhat.workshop.people.notification;

import com.fasterxml.jackson.annotation.JsonInclude;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record NotificationRecipients(String type, String entityRef) {

    public static NotificationRecipients broadcast() {
        return new NotificationRecipients("broadcast", null);
    }

    public static NotificationRecipients entity(String entityRef) {
        return new NotificationRecipients("entity", entityRef);
    }
}
