# Persistence

The workshop uses PostgreSQL with Hibernate ORM Panache and Flyway migrations.

## Entity model

`Person` is a Panache entity mapped to the `people` table:

```java
@Entity
public class Person extends PanacheEntity {
    public String firstName;
    public String lastName;
    public Integer age;
}
```

## Flyway

The initial schema is defined in `db/migration/V1__create_people.sql`:

```sql
CREATE TABLE people (
    id BIGSERIAL PRIMARY KEY,
    first_name VARCHAR(255) NOT NULL,
    last_name VARCHAR(255) NOT NULL,
    age INTEGER NOT NULL
);
```

Flyway runs automatically on application startup.

## Configuration

OpenShift injects database settings through environment variables on the `people-backend` Deployment:

- `QUARKUS_DATASOURCE_JDBC_URL`
- `QUARKUS_DATASOURCE_USERNAME`
- `QUARKUS_DATASOURCE_PASSWORD`

## Troubleshooting

If `/q/health/ready` reports the database check as DOWN:

1. Confirm the `people-postgres` pod is running.
2. Run `./scripts/repair-people-app.sh`.
3. For a clean database reset: `REPAIR_RESET_POSTGRES_DATA=true ./scripts/repair-people-app.sh`.
