COMPOSE = docker compose
CERTS_DIR = certs
CERTS_MARKER = $(CERTS_DIR)/ca.crt

.PHONY: up down restart logs build clean certs

## Levanta todo: genera certs si faltan y arranca los contenedores
up: $(CERTS_MARKER) .env
	$(COMPOSE) up -d

## Genera los certificados mTLS (solo si no existen)
certs: $(CERTS_MARKER)

$(CERTS_MARKER):
	@echo "→ Generando certificados mTLS..."
	@bash scripts/generate_certs.sh

## Crea .env desde .env.example si no existe
.env:
	@echo "→ Creando .env desde .env.example (completa las credenciales)"
	@cp .env.example .env

## Reconstruye imágenes y levanta
build:
	$(COMPOSE) build
	$(COMPOSE) up -d

## Para y elimina contenedores (conserva volumes)
down:
	$(COMPOSE) down

## Para, reconstruye y vuelve a levantar
restart: down build

## Logs en tiempo real (usar: make logs s=openfga)
logs:
	$(COMPOSE) logs -f $(s)

## Elimina certs y baja contenedores con volumes
clean:
	$(COMPOSE) down -v
	rm -rf $(CERTS_DIR)
	@echo "→ Limpieza completa. Ejecuta 'make up' para empezar de nuevo."
