#!/bin/bash

# Rutas de archivos
BASE_DIR="openfga"
MODEL_FILE="$BASE_DIR/model.fga.yaml"
CLEAN_MODEL="$BASE_DIR/model_clean.fga"
TUPLES_JSON="$BASE_DIR/tuples.json"

# Configuración OpenFGA
STORE_NAME="Mi_Aplicacion"
FGA_API_URL="http://localhost:8081"
IMAGE_CLI="docker.io/openfga/cli:v0.7.8"
IMAGE_YQ="docker.io/mikefarah/yq:latest"
IMAGE_JQ="ghcr.io/jqlang/jq:latest"

source ../.env
set +a

echo "🚀 Iniciando despliegue de OpenFGA..."

# 1. Ejecutar migraciones de OpenFGA directamente con docker run
echo "⚙️ Ejecutando migraciones de OpenFGA (docker run openfga/openfga:latest migrate)..."
docker run --rm --network=host \
  -e OPENFGA_DATASTORE_ENGINE=postgres \
  -e OPENFGA_DATASTORE_URI="postgres://postgres:password@localhost:5432/openfga?sslmode=disable" \
  openfga/openfga:latest migrate || {
  echo "❌ Error al ejecutar las migraciones de OpenFGA"
  exit 1
}

# 2. Función para ejecutar comandos de Docker de forma segura
fga_exec() {
    docker run --rm --network=host \
      -v "$(pwd):/app" -w /app "$@"
}

# Ejecuta jq sin depender de jq local
jq_exec() {
    docker run --rm -i $IMAGE_JQ "$@"
}

# 3. Intentar crear o recuperar el Store
echo "📦 Verificando Store: $STORE_NAME..."
CREATE_OUT=$(fga_exec $IMAGE_CLI store create --name "$STORE_NAME" --api-url "$FGA_API_URL" 2>/dev/null)
STORE_ID=$(echo "$CREATE_OUT" | jq_exec -r '.id // empty')

if [ -z "$STORE_ID" ] || [ "$STORE_ID" == "null" ]; then
    echo "⚠️  El Store ya existe o requiere recuperación. Buscando ID..."
    LIST_OUT=$(fga_exec $IMAGE_CLI store list --api-url "$FGA_API_URL" --client-id "$FGA_CLIENT_ID" --client-secret "$FGA_CLIENT_SECRET" --api-token-issuer "http://localhost:8080" --api-audience "$FGA_CLIENT_ID" --api-scopes "stores:read")
    STORE_ID=$(echo "$LIST_OUT" | jq_exec -r --arg name "$STORE_NAME" '.stores | map(select(.name == $name)) | sort_by(.created_at) | last | .id')
fi

# Validar ULID (formato OpenFGA)
if [[ ! "$STORE_ID" =~ ^[0-9A-HJKMNP-TV-Z]{26}$ ]]; then
    echo "❌ Error: No se pudo obtener un Store ID válido. ¿Está OpenFGA corriendo en $FGA_API_URL?"
    exit 1
fi

echo "✅ Store ID detectado: $STORE_ID"

# 3. Procesar y escribir el Modelo
echo "📝 Procesando modelo desde $MODEL_FILE..."
# Extraemos el contenido DSL (limpiando el formato YAML)
sed -n '/model: |/,/tuples:/p' "$MODEL_FILE" | grep -v "model: |" | grep -v "tuples:" | sed 's/^  //' > "$CLEAN_MODEL"

RESULT=$(fga_exec $IMAGE_CLI model write --store-id "$STORE_ID" --file "$CLEAN_MODEL" --api-url "$FGA_API_URL")
MODEL_ID=$(echo "$RESULT" | jq_exec -r '.authorization_model_id')

if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" == "null" ]; then
    echo "❌ Error al escribir el modelo. Revisa $CLEAN_MODEL"
    exit 1
fi

# 4. Subir las Tuplas
echo "📊 Extrayendo tuplas..."
# Usamos yq para generar el JSON temporal
docker run --rm -v "$(pwd):/app" -w /app $IMAGE_YQ eval '.tuples' "$MODEL_FILE" -o json > "$TUPLES_JSON"

echo "📤 Subiendo tuplas al Store..."
fga_exec $IMAGE_CLI tuple write --store-id "$STORE_ID" --file "$TUPLES_JSON" --api-url "$FGA_API_URL"

echo "------------------------------------------------"
echo "🎉 CONFIGURACIÓN COMPLETADA"
echo "Store ID: $STORE_ID"
echo "Model ID: $MODEL_ID"
echo "------------------------------------------------"