# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

B2B identity and authorization demo using Go gRPC microservices with mTLS, OIDC authentication (Zitadel), and fine-grained authorization (OpenFGA).

## Architecture

```
HTTP Request → APISIX (:9080) → Service B (:50052) → Service A (:50051)
                  ↓
            [OIDC + OpenFGA]
                  ↓
            Zitadel (:8080) + OpenFGA (:8081/:8082)
                  ↓
            PostgreSQL (:5432)
```

**Components:**
- **APISIX**: API gateway with OIDC plugin (Zitadel), custom `authz-openfga.lua` plugin, and gRPC transcoding
- **Service A/B**: Go gRPC services with mTLS; Service B proxies to Service A, propagating user metadata via gRPC headers (`x-user-id`, `x-tenant-id`)
- **Zitadel**: B2B identity provider (OIDC/OAuth2)
- **OpenFGA**: Relationship-based authorization (users as members of tenants)

## Development Commands

### Initial Setup
```bash
# 1. Generate mTLS certificates
cd scripts && ./generate_certs.sh && cd ..

# 2. Configure OIDC credentials (copy .env.example to .env and fill in values from Zitadel)
cp .env.example .env

# 3. Start all services
docker compose up -d

# 4. Deploy OpenFGA model and tuples (after services are up)
./scripts/deploy-model.sh
```

### Common Operations
```bash
# Rebuild a single service
docker compose build service_a
docker compose up -d service_a

# View logs
docker compose logs -f apisix
docker compose logs -f service_a service_b

# Restart stack
docker compose down && docker compose up -d
```

## Key Files

| File | Purpose |
|------|---------|
| `apisix_conf/apisix.yaml` | Routes, gRPC transcoding, plugin configs |
| `apisix_conf/plugins/authz-openfga.lua` | Custom authorization plugin |
| `openfga/model.fga.yaml` | Authorization model (DSL) and initial tuples |
| `service_a/main.go` | Main gRPC server with mTLS |
| `service_b/main.go` | Proxy service with metadata propagation |

## Environment Variables

Required in `.env` (see `.env.example`):
- `APISIX_OIDC_CLIENT_ID` / `APISIX_OIDC_CLIENT_SECRET`: Zitadel OIDC credentials
- `APISIX_CLIENT_CERT` / `APISIX_CLIENT_KEY`: Client certificate for APISIX→OpenFGA mTLS
