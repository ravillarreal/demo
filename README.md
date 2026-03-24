# Para iniciar:

1. Ejecutar scripts

```
cd scripts
./generate_certs.sh
./deploy-model.sh
```

luego docker compose up -d


# Comandos comunes

```
docker run --rm --network demo_default openfga/cli store list --debug --api-url "http://openfga:8081" --api-token-issuer "http://zitadel:8080/oauth/v2/token" --client-id "openfga" --client-secret "Kp20HSEDsywLrtqxizQojMRfNFaS7HuXfAtZQIPMwouf7RbpQH4qOWgaeMPiJHIs" --api-scopes "asd"
```

```
docker run --rm --network demo_default curlimages/curl http://openfga:8081
```