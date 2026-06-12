package com.redhat.workshop.people.resource;

import com.redhat.workshop.people.dto.PersonRequest;
import com.redhat.workshop.people.dto.PersonResponse;
import com.redhat.workshop.people.entity.Person;
import jakarta.annotation.security.RolesAllowed;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

@Path("/api/people")
@Tag(name = "People", description = "CRUD operations for Person records")
@SecurityRequirement(name = "bearerAuth")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@RolesAllowed("people-crud")
public class PersonResource {

    @GET
    @Operation(summary = "List all people")
    @APIResponse(responseCode = "200", description = "List of people",
            content = @Content(schema = @Schema(implementation = PersonResponse.class)))
    public List<PersonResponse> list() {
        return Person.<Person>listAll().stream()
                .map(PersonResponse::from)
                .toList();
    }

    @GET
    @Path("/{id}")
    @Operation(summary = "Get a person by ID")
    public PersonResponse get(@PathParam("id") Long id) {
        return PersonResponse.from(findPerson(id));
    }

    @POST
    @Transactional
    @Operation(summary = "Create a person")
    @APIResponse(responseCode = "201", description = "Person created")
    public Response create(PersonRequest request) {
        validate(request);
        Person person = new Person();
        person.firstName = request.firstName().trim();
        person.lastName = request.lastName().trim();
        person.age = request.age();
        person.persist();
        return Response.status(Response.Status.CREATED).entity(PersonResponse.from(person)).build();
    }

    @PUT
    @Path("/{id}")
    @Transactional
    @Operation(summary = "Update a person")
    public PersonResponse update(@PathParam("id") Long id, PersonRequest request) {
        validate(request);
        Person person = findPerson(id);
        person.firstName = request.firstName().trim();
        person.lastName = request.lastName().trim();
        person.age = request.age();
        return PersonResponse.from(person);
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    @Operation(summary = "Delete a person")
    @APIResponse(responseCode = "204", description = "Person deleted")
    public Response delete(@PathParam("id") Long id) {
        findPerson(id).delete();
        return Response.noContent().build();
    }

    private Person findPerson(Long id) {
        Person person = Person.findById(id);
        if (person == null) {
            throw new NotFoundException("Person not found: " + id);
        }
        return person;
    }

    private void validate(PersonRequest request) {
        if (request.firstName() == null || request.firstName().isBlank()) {
            throw new IllegalArgumentException("firstName is required");
        }
        if (request.lastName() == null || request.lastName().isBlank()) {
            throw new IllegalArgumentException("lastName is required");
        }
        if (request.age() < 0 || request.age() > 150) {
            throw new IllegalArgumentException("age must be between 0 and 150");
        }
    }
}
