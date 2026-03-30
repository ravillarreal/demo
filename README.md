# Para iniciar:

1. Ejecutar scripts

```
cd scripts
./generate_certs.sh
./deploy-model.sh
```

luego docker compose up -d

# Que falta:
- Inyectar el X-TenantID de Zitadel en los upstreams. (listo)
- Usar scopes de Zitadel para Coarse Grained con authz-casbin Casbin
- Hacer un Shared Auth Library con OpenFGA para mis microservicios, que pueda ejecutar la lógica de autorización.
- Implementar arquitectura que desacople autorización fina de lógica de negocio en Go para microservicios. (DDD optimizado)