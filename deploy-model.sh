#!/bin/bash

STORE_NAME="Mi_Aplicacion"
MODEL_FILE="model.fga.yaml" 
FGA_API_URL="http://localhost:8081"
IMAGE="openfga/cli:v0.7.8"

echo "🚀 Iniciando despliegue de OpenFGA..."

# 1. Intentar crear el Store
CREATE_OUT=$(docker run --rm --network=host $IMAGE store create --name "$STORE_NAME" --api-url "$FGA_API_URL" 2>/dev/null)
STORE_ID=$(echo $CREATE_OUT | jq -r .id)

# 2. Si no se creó (porque ya existe), buscar el ID más reciente con ese nombre
if [ "$STORE_ID" == "null" ] || [ -z "$STORE_ID" ]; then
    echo "⚠️  El Store ya existe. Recuperando el ID más reciente..."
    
    # Explicación: Listamos, filtramos por nombre, ordenamos por fecha y tomamos el último
    STORE_ID=$(docker run --rm --network=host $IMAGE store list --api-url "$FGA_API_URL" | \
      jq -r ".stores | map(select(.name == \"$STORE_NAME\")) | sort_by(.created_at) | last | .id")
fi

# Validar que ahora sí tenemos un único ULID
if [[ ! "$STORE_ID" =~ ^[0-9A-HJKMNP-TV-Z]{26}$ ]]; then
    echo "❌ Error crítico: No se pudo determinar un Store ID único."
    echo "Valor obtenido: $STORE_ID"
    exit 1
fi

echo "✅ Store ID único detectado: $STORE_ID"

# 3. Escribir el Modelo
echo "📝 Procesando y escribiendo modelo..."

# Extraemos el contenido dentro de la etiqueta 'model: |' 
# Este comando sed busca lo que hay entre 'model: |' y 'tuples:' y limpia la indentación
sed -n '/model: |/,/tuples:/p' model.fga.yaml | grep -v "model: |" | grep -v "tuples:" | sed 's/^  //' > model_clean.fga

# Subimos el archivo limpio
RESULT=$(docker run --rm --network=host -v "$(pwd):/app" -w /app $IMAGE \
  model write --store-id "$STORE_ID" --file model_clean.fga --api-url "$FGA_API_URL")

MODEL_ID=$(echo $RESULT | jq -r .authorization_model_id)

if [ "$MODEL_ID" == "null" ] || [ -z "$MODEL_ID" ]; then
    echo "❌ Error al escribir el modelo. Revisa model_clean.fga"
    exit 1
fi

# 4. Subir las Tuplas
echo "      Subiendo tuplas iniciales..."

# Extraemos solo la lista de tuplas y la convertimos a un JSON temporal que el CLI entienda
# Usamos jq para extraer el array que está bajo la clave 'tuples'
docker run --rm -v "$(pwd):/app" -w /app mikefarah/yq eval '.tuples' model.fga.yaml -o json > tuples.json

docker run --rm --network=host -v "$(pwd):/app" -w /app $IMAGE \
  tuple write --store-id "$STORE_ID" --file tuples.json --api-url "$FGA_API_URL"

echo "------------------------------------------------"
echo "🎉 CONFIGURACIÓN COMPLETADA"
echo "Store ID: $STORE_ID"
echo "Model ID: $MODEL_ID"
echo "------------------------------------------------"