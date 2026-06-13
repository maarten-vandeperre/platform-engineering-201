# Quarkus Workshop Guide

This guide explains how the **People Service** backend uses [Quarkus](https://quarkus.io/) in the Platform Engineering 201 workshop.

## What you will learn

- How the workshop Quarkus project is structured
- How to run and test the API locally and on OpenShift
- How persistence, OpenAPI, and Keycloak integrate with the service
- How the service appears in Red Hat Developer Hub

## Workshop stack

| Layer | Technology |
|-------|------------|
| API | Quarkus 3.x + RESTEasy Reactive |
| Database | PostgreSQL + Hibernate ORM Panache |
| Security | Keycloak OIDC (`people-crud` role) |
| Deployment | OpenShift Deployment + Route |
| Catalog | Developer Hub API + TechDocs |

Start with [Getting started](getting-started.md).
