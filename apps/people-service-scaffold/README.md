# ${{ values.componentTitle or values.componentId }}

${{ values.description }}

Java Quarkus backend with PostgreSQL and a React frontend for CRUD operations on `Person` records.

## Local development

### Backend

```bash
cd backend
./mvnw quarkus:dev
```

Set database environment variables or start PostgreSQL locally:

```bash
export DB_JDBC_URL=jdbc:postgresql://localhost:5432/people
export DB_USERNAME=people
export DB_PASSWORD=people
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

The Vite dev server proxies `/api` requests to `http://localhost:8080`.

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/people` | List all people |
| GET | `/api/people/{id}` | Get one person |
| POST | `/api/people` | Create a person |
| PUT | `/api/people/{id}` | Update a person |
| DELETE | `/api/people/{id}` | Delete a person |

Health check: `GET /q/health`

## Container images

Images are built and published by GitHub Actions to GitHub Container Registry:

- `ghcr.io/<owner>/<repo>/people-backend:latest`
- `ghcr.io/<owner>/<repo>/people-frontend:latest`

See `.github/workflows/build-and-push.yaml`.
