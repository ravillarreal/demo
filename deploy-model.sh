#!/bin/bash

# Configuración
STORE_NAME="b2b_system"
MODEL_FILE="./model.fga.yaml" # Asegúrate de que este archivo esté en tu carpeta actual

echo "🚀 Iniciando despliegue de OpenFGA..."

# 1. Crear el Store (o recuperarlo si ya existe)
# Usamos fga-cli de forma temporal (--rm)
STORE_ID=$(docker run --rm --network=host -v $(pwd):/app -w /app openfga/fga-cli \
  store create --name "$STORE_NAME" --api-url http://localhost:8081 | jq -r .id)

if [ "$STORE_ID" == "null" ] || [ -z "$STORE_ID" ]; then
    echo "⚠️  El Store ya existe o hubo un error. Buscando ID..."
    STORE_ID=$(docker run --rm --network=host openfga/fga-cli \
      store list --api-url http://localhost:8081 | grep "$STORE_NAME" | awk '{print $1}')
fi

echo "✅ Store ID: $STORE_ID"

# 2. Escribir el Modelo y las Tuplas iniciales
# fga-cli puede leer un archivo que contenga tanto el modelo como las tuplas de prueba
echo "📝 Escribiendo modelo desde $MODEL_FILE..."
RESULT=$(docker run --rm --network=host -v $(pwd):/app -w /app openfga/fga-cli \
  model write --store-id "$STORE_ID" --file model.fga.yaml --api-url http://localhost:8081)

MODEL_ID=$(echo $RESULT | jq -r .authorization_model_id)

echo "------------------------------------------------"
echo "🎉 CONFIGURACIÓN COMPLETADA"
echo "Store ID: $STORE_ID"
echo "Model ID: $MODEL_ID"
echo "------------------------------------------------"
echo "Próximo paso: Actualiza 'local store_id = \"$STORE_ID\"' en tu apisix.yaml"