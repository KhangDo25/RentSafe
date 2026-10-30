# Phase 1 architecture

RentSafe starts as a modular monolith: one Spring Boot application and one MongoDB deployment per customer installation. A single deployable backend keeps the first version straightforward to run and explain. As the application grows, related code can be grouped by business area inside `com.rentsafe` without splitting into services.

The current backend has two small pieces:

- `RentSafeApplication` starts Spring Boot and enables component discovery from `com.rentsafe`.
- `api.HealthController` exposes `GET /api/health` as a simple JSON liveness response and `GET /api/health/readiness` as a MongoDB connectivity check.

Spring Data MongoDB is the persistence foundation. There are no business collections or workflows yet. Future modules own their collections, indexes, validation, and data-versioning approach as described in `mongodb-architecture.md`.

The React app is a separate Vite development/build target. It currently presents a static landing page and does not call the API. Docker Compose provides a MongoDB replica set for development, with persistent named storage and an internal-only Docker network. MongoDB has no default host-port publication; `docker-compose.dev.yml` is the development-only loopback override for a Windows-hosted backend. The frontend never receives database credentials.
