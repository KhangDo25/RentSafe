# RentSafe

RentSafe is a modular monolith foundation for managing rental assets such as vehicles, equipment, and machinery. Phase 1 establishes the Spring Boot API, React frontend, and MongoDB development setup. It does not include rental business workflows, authentication, or asset records yet.

## Current status

- Spring Boot 3 / Java 21 API with liveness (`GET /api/health`) and MongoDB readiness (`GET /api/health/readiness`) endpoints.
- React, TypeScript, and Vite landing page.
- Spring Data MongoDB configuration; development connects to MongoDB Atlas through environment variables.
- There are no business collections or workflows in Phase 1.

## Prerequisites

- JDK 21. Set `JAVA_HOME` to the JDK 21 installation and ensure `%JAVA_HOME%\bin` is on `PATH`.
- Apache Maven 3.9 or newer, with `mvn` available on `PATH`.
- Node.js 20.19+ or 22.12+ and npm.
- Docker Desktop only when working on the separate self-hosted deployment path.

## Run the API on Windows

The development backend connects to MongoDB Atlas. Copy the template, then set the Atlas URI only in your local ignored `.env` file:

```powershell
Copy-Item .env.example .env
```

Set `MONGODB_DATABASE=rentsafe` and set `MONGODB_URI` to an Atlas SRV URI for the assigned Atlas database user and cluster. Include `serverSelectionTimeoutMS=5000`, `connectTimeoutMS=5000`, and `socketTimeoutMS=10000` as URI query parameters. Do not put the URI in source code, `.env.example`, or a frontend environment variable.

If the password contains reserved URI characters such as `@`, `:`, `/`, `?`, `#`, `[`, or `]`, URL-encode it before placing it in `MONGODB_URI`. Do not URL-encode the complete URI—only the username/password components when required.

Spring Boot does not load `.env` by itself. In the PowerShell session that starts the API, load the two values without printing them:

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^(MONGODB_DATABASE|MONGODB_URI)=(.*)$') {
    Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2]
  }
}
```

Then run the API:

```powershell
cd backend
mvn spring-boot:run
```

The bundled Docker Compose files remain for self-hosted installations. They use an internal MongoDB network by default and are not needed for Atlas development. Configure their separate `MONGO_*` deployment secrets through the production deployment environment; do not reuse or commit the Atlas development `.env` file.

Check `http://localhost:8080/api/health` for application liveness and `http://localhost:8080/api/health/readiness` for MongoDB connectivity. The readiness endpoint returns HTTP 503 without connection details when MongoDB is unavailable. The API requires `MONGODB_URI` and `MONGODB_DATABASE`; it has no credential defaults.

## Run the frontend on Windows

In a second PowerShell window, from the repository root:

```powershell
cd frontend
npm install
npm run dev
```

Open the local URL printed by Vite (normally `http://localhost:5173`). To create a production build, run `npm run build` in `frontend`.

## Verify

Run backend tests and package the API with `cd backend; mvn verify`. Build the frontend with `cd frontend; npm run build`. The liveness endpoint does not query MongoDB; readiness does.

## Architecture notes

The backend is one Spring Boot application, organized by package; features can later be grouped into modules under `com.rentsafe`. The API layer currently contains only health endpoints. Spring Data MongoDB is the persistence foundation. The frontend is a separate Vite app and has no business data or API integration in this phase.
