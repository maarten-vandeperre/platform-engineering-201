package com.redhat.workshop.people.notification;

public record NotificationRequest(NotificationRecipients recipients, NotificationPayload payload) {
}
