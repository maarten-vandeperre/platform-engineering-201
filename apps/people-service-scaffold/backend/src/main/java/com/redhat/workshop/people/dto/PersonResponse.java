package com.redhat.workshop.people.dto;

import com.redhat.workshop.people.entity.Person;

public record PersonResponse(Long id, String firstName, String lastName, int age) {

    public static PersonResponse from(Person person) {
        return new PersonResponse(person.id, person.firstName, person.lastName, person.age);
    }
}
