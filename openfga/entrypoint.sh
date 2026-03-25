#!/bin/sh
set -e

STORE_NAME="${FGA_STORE_NAME:-demo}"
MODEL_FILE="/openfga/model.fga"
TESTS_FILE="/openfga/model.fga.yaml"

AUTH_ARGS="--api-url ${FGA_API_URL} \
  --client-id ${FGA_CLIENT_ID} \
  --client-secret ${FGA_CLIENT_SECRET} \
  --api-token-issuer ${FGA_API_TOKEN_ISSUER}/oauth/v2/token \
  --api-audience ${FGA_API_AUDIENCE} \
  --api-scopes asd"

echo $FGA_CLIENT_ID

# ── 1. Testear el modelo localmente (sin necesitar OpenFGA corriendo) ────────
echo "==> Testeando modelo de autorización..."
fga model test --tests "$TESTS_FILE"
echo "==> Tests pasados!"

# ── 2. Esperar a que OpenFGA esté listo ──────────────────────────────────────
echo "==> Esperando a OpenFGA en ${FGA_API_URL}..."
until fga store list --debug $AUTH_ARGS > /dev/null; do
  echo "    OpenFGA no está listo, reintentando en 3s..."
  sleep 3
done
echo "==> OpenFGA disponible!"

# ── 3. Buscar o crear el store ───────────────────────────────────────────────
echo "==> Buscando store '${STORE_NAME}'..."
STORE_ID=$(fga store list $AUTH_ARGS \
  | jq -r --arg name "$STORE_NAME" '.stores[]? | select(.name == $name) | .id' \
  | head -1)

if [ -z "$STORE_ID" ]; then
  echo "==> Store no encontrado. Creando '${STORE_NAME}'..."
  STORE_ID=$(fga store create --name "$STORE_NAME" $AUTH_ARGS \
    | jq -r '.store.id')
  echo "==> Store creado: ${STORE_ID}"
else
  echo "==> Store encontrado: ${STORE_ID}"
fi

# ── 4. Comparar modelo actual con el local y escribir solo si cambió ─────────
echo "==> Verificando modelo actual en el store..."
ORIGINAL_MODEL=$(fga model get --store-id "$STORE_ID" $AUTH_ARGS --format=fga) || true
echo "modelo encontrado: $ORIGINAL_MODEL"

MODEL_ID=""
if [ -z "$ORIGINAL_MODEL" ]; then
  echo "==> No hay modelo en el store, escribiendo..."
  MODEL_ID=$(fga model write --store-id "$STORE_ID" --file "$MODEL_FILE" \
    $AUTH_ARGS | jq -r '.authorization_model_id')
  echo "==> Modelo escrito: ${MODEL_ID}"
elif [ "$ORIGINAL_MODEL" = "$(cat "$MODEL_FILE")" ]; then
  echo "==> El modelo no ha cambiado, omitiendo write."
  MODEL_ID=$(fga model get --store-id "$STORE_ID" $AUTH_ARGS --field id --format json \
    | jq -r '.id')
else
  echo "==> El modelo ha cambiado, actualizando..."
  MODEL_ID=$(fga model write --store-id "$STORE_ID" --file "$MODEL_FILE" \
    $AUTH_ARGS | jq -r '.authorization_model_id')
  echo "==> Modelo actualizado: ${MODEL_ID}"
fi

echo ""
echo "Setup completado."
echo "  Store ID:             ${STORE_ID}"
echo "  Authorization Model:  ${MODEL_ID}"
