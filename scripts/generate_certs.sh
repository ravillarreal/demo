#!/bin/bash

# Configuración
CERT_DIR="./certs"
mkdir -p $CERT_DIR

# 1. Generar la Autoridad Certificadora (Root CA)
echo "Generando CA..."
openssl genrsa -out $CERT_DIR/ca.key 4096
openssl req -x509 -new -nodes -key $CERT_DIR/ca.key -sha256 -days 3650 \
    -out $CERT_DIR/ca.crt \
    -subj "/CN=ZeroTrust-Internal-CA"

# 2. Generar Certificado para el Servidor gRPC (con SAN para Docker)
echo "Generando certificado para el Servidor gRPC..."
openssl genrsa -out $CERT_DIR/server.key 2048

# Crear archivo de configuración temporal para SAN
# Cambia 'grpc-server' por el nombre de tu servicio en docker-compose
cat > $CERT_DIR/server.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = go-app
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = go-app
DNS.2 = localhost
EOF

openssl req -new -key $CERT_DIR/server.key -out $CERT_DIR/server.csr -config $CERT_DIR/server.conf

openssl x509 -req -in $CERT_DIR/server.csr -CA $CERT_DIR/ca.crt -CAkey $CERT_DIR/ca.key \
    -CAcreateserial -out $CERT_DIR/server.crt -days 365 -sha256 -extensions v3_req -extfile $CERT_DIR/server.conf

# 3. Generar Certificado de Cliente para APISIX
echo "Generando certificado para APISIX Gateway..."
openssl genrsa -out $CERT_DIR/apisix-client.key 2048

openssl req -new -key $CERT_DIR/apisix-client.key -out $CERT_DIR/apisix-client.csr \
    -subj "/CN=apisix-gateway"

openssl x509 -req -in $CERT_DIR/apisix-client.csr -CA $CERT_DIR/ca.crt -CAkey $CERT_DIR/ca.key \
    -CAcreateserial -out $CERT_DIR/apisix-client.crt -days 365 -sha256

# Limpieza de archivos temporales
rm $CERT_DIR/*.csr $CERT_DIR/*.conf $CERT_DIR/*.srl

echo "¡Éxito! Certificados generados en $CERT_DIR"
ls -l $CERT_DIR