# Organization entity diagram

Model for **Nile Digital**: 3 teams, 8 employees, 2 platforms, 4 applications, PostgreSQL, Keycloak, and Kafka.

## Summary

| Entity type | Count | Names |
|-------------|------:|-------|
| Organization | 1 | Nile Digital |
| Teams | 3 | Platform Engineering, Product Delivery, Data & Integration |
| Employees | 8 | 3 + 3 + 2 across teams |
| Platforms | 2 | People Platform, Integration Platform |
| Applications | 4 | People Service, Billing Service, Inventory Service, Order Processor |
| Database | 1 | Workshop PostgreSQL |
| Identity | 1 | Workshop Keycloak (secures all apps) |
| Kafka | 1 cluster, 2 topics | `person-events`, `order-events` (used by Order Processor) |

## Team membership

| Team | Members |
|------|---------|
| **Platform Engineering** (3) | Alice Chen, Bob Martin, Carol Rivera |
| **Product Delivery** (3) | Dave Kumar, Eve Johnson, Frank Okonkwo |
| **Data & Integration** (2) | Grace Lombardi, Henry Petrov |

## Entity relationship diagram

```mermaid
erDiagram
    ORGANIZATION ||--|{ TEAM : "contains"
    TEAM ||--|{ EMPLOYEE : "employs"
    PLATFORM ||--|{ APPLICATION : "hosts"
    TEAM ||--o{ APPLICATION : "owns"
    APPLICATION }o--|| POSTGRESQL : "persists to"
    APPLICATION }o--|| KEYCLOAK : "secured by"
    APPLICATION ||--o| KAFKA_CLUSTER : "streams via"
    KAFKA_CLUSTER ||--|{ KAFKA_TOPIC : "contains"

    ORGANIZATION {
        string name "Nile Digital"
    }

    TEAM {
        string platform_engineering "3 employees"
        string product_delivery "3 employees"
        string data_integration "2 employees"
    }

    EMPLOYEE {
        string id "8 users in catalog"
    }

    PLATFORM {
        string people_platform "People Platform"
        string integration_platform "Integration Platform"
    }

    APPLICATION {
        string people_service "People Service"
        string billing_service "Billing Service"
        string inventory_service "Inventory Service"
        string order_processor "Order Processor (Kafka)"
    }

    POSTGRESQL {
        string name "workshop-postgresql"
    }

    KEYCLOAK {
        string name "workshop-keycloak"
    }

    KAFKA_CLUSTER {
        string name "workshop-kafka"
    }

    KAFKA_TOPIC {
        string person_events "person-events"
        string order_events "order-events"
    }
```

## Architecture view

```mermaid
flowchart TB
    subgraph Org["Organization: Nile Digital"]
        PT[Platform Engineering<br/>3 employees]
        PD[Product Delivery<br/>3 employees]
        DT[Data & Integration<br/>2 employees]
    end

    subgraph Platforms["2 Platforms"]
        PP[People Platform]
        IP[Integration Platform]
    end

    subgraph Apps["4 Applications"]
        PS[People Service]
        BS[Billing Service]
        IS[Inventory Service]
        OP[Order Processor]
    end

    subgraph Data["Shared infrastructure"]
        DB[(PostgreSQL)]
        KC[Keycloak OIDC]
        KF{{Kafka cluster}}
        T1[person-events topic]
        T2[order-events topic]
    end

    PT --> PP
    PD --> PP
    DT --> IP

    PT -.-> KC
    PD --> PS
    PD --> BS
    PD --> IS
    DT --> OP

    PP --> PS
    PP --> BS
    PP --> IS
    IP --> OP

    PS --> DB
    BS --> DB
    IS --> DB

    PS --> KC
    BS --> KC
    IS --> KC
    OP --> KC

    OP --> KF
    KF --> T1
    KF --> T2
    OP --> T1
    OP --> T2
```

## Catalog entity map (Developer Hub)

```mermaid
flowchart LR
    subgraph Groups
        G0[nile-digital]
        G1[platform-team]
        G2[product-team]
        G3[data-team]
    end

    subgraph Users
        U1[alice-chen]
        U2[bob-martin]
        U3[carol-rivera]
        U4[dave-kumar]
        U5[eve-johnson]
        U6[frank-okonkwo]
        U7[grace-lombardi]
        U8[henry-petrov]
    end

    subgraph Systems
        S1[people-platform]
        S2[integration-platform]
    end

    subgraph Components
        C1[people-service]
        C2[billing-service]
        C3[inventory-service]
        C4[order-processor]
    end

    subgraph Resources
        R1[workshop-postgresql]
        R2[workshop-keycloak]
        R3[workshop-kafka]
        R4[person-events-topic]
        R5[order-events-topic]
    end

    G0 --> G1
    G0 --> G2
    G0 --> G3
    G1 --> U1 & U2 & U3
    G2 --> U4 & U5 & U6
    G3 --> U7 & U8

    G2 --> C1 & C2 & C3
    G3 --> C4
    S1 --> C1 & C2 & C3
    S2 --> C4

    C1 & C2 & C3 --> R1
    C1 & C2 & C3 & C4 --> R2
    C4 --> R3
    C4 --> R4 & R5
    R4 & R5 --> R3
```

## Application dependencies

| Application | Platform | Team | PostgreSQL | Keycloak | Kafka | Topics |
|-------------|----------|------|:----------:|:--------:|:-----:|--------|
| People Service | People Platform | Product Delivery | yes | yes | — | — |
| Billing Service | People Platform | Product Delivery | yes | yes | — | — |
| Inventory Service | People Platform | Product Delivery | yes | yes | — | — |
| Order Processor | Integration Platform | Data & Integration | — | yes | yes | `person-events`, `order-events` |

Catalog definitions live in:

- `manifests/gitops/catalog/entities/organization-model.yaml`
- `manifests/gitops/catalog/entities/people-service.yaml` (People Service + People Platform)
