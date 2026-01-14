#!/bin/bash
mkdir -p certs
cd certs

# 1. Generar la CA (Autoridad Certificadora)
openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -out ca.crt -subj "/CN=MyInternalCA"

# Función para generar certs con SAN (Subject Alternative Names)
generate_cert() {
    NAME=$1
    echo "Generando certificado para: $NAME"
    
    # Crear archivo de configuración temporal para SAN
    cat > ${NAME}.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${NAME}
DNS.2 = localhost
EOF

    openssl genrsa -out ${NAME}.key 2048
    openssl req -new -key ${NAME}.key -out ${NAME}.csr -subj "/CN=${NAME}"
    openssl x509 -req -in ${NAME}.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -out ${NAME}.crt -days 365 -extfile ${NAME}.ext
}

# 2. Generar para cada componente
generate_cert "apisix"
generate_cert "openfga"
generate_cert "service_a"
generate_cert "service_b"

# Limpiar
rm *.csr *.ext *.srl