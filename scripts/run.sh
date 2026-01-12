#!/bin/bash
# Cargar contenido de los certs en variables
export APISIX_CLIENT_CERT=$(cat ../certs/apisix-client.crt)
export APISIX_CLIENT_KEY=$(cat ../certs/apisix-client.key)

docker compose up -d