# Para iniciar:

1. Ejecutar scripts

```
cd scripts
./generate_certs.sh
./deploy-model.sh
```

luego docker compose up -d

# Que falta:
- Inyectar el X-TenantID de Zitadel en los upstreams.
- Entender los scopes de Zitadel y usarlos para hacer Coarse grained autorization para denegar rutas sin ir a openfga.
- Implementar arquitectura limpia que desacople autorización fina de lógica de negocio en Go para microservicios.