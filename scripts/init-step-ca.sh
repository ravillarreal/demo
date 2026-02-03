#!/bin/bash
set -e

# Configuration
CERT_VALIDITY_HOURS="${CERT_VALIDITY_HOURS:-24}"
CERTS_DIR="./certs"
SERVICES=("apisix" "openfga" "service_a" "service_b")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Wait for step-ca to be healthy
wait_for_step_ca() {
    log "Waiting for step-ca to be healthy..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if podman compose exec -T step-ca step ca health 2>/dev/null | grep -q "ok"; then
            log "step-ca is healthy"
            return 0
        fi
        log "Attempt $attempt/$max_attempts: step-ca not ready yet"
        sleep 2
        ((attempt++))
    done

    log "ERROR: step-ca did not become healthy in time"
    return 1
}

# Bootstrap - copy the root CA certificate
bootstrap_ca() {
    log "Copying root CA certificate..."

    mkdir -p "$CERTS_DIR"

    # Copy the root CA certificate from step-ca container
    podman compose exec -T step-ca cat /home/step/certs/root_ca.crt > "$CERTS_DIR/ca.crt"

    if [ ! -s "$CERTS_DIR/ca.crt" ]; then
        log "ERROR: Failed to copy root CA certificate"
        return 1
    fi

    log "Root CA certificate copied to $CERTS_DIR/ca.crt"
    return 0
}

# Issue initial certificates
issue_initial_certificates() {
    log "Issuing initial certificates..."

    for service in "${SERVICES[@]}"; do
        log "Issuing certificate for $service..."

        # Issue certificate using step-ca container
        # The certificate is written to /certs which is mounted from ./certs
        podman compose exec -T step-ca sh -c "
            step ca certificate '$service' \
                '/certs/${service}.crt' \
                '/certs/${service}.key' \
                --provisioner='admin' \
                --provisioner-password-file=/home/step/secrets/password \
                --san='$service' \
                --san='localhost' \
                --not-after='${CERT_VALIDITY_HOURS}h' \
                --force
        "

        if [ $? -eq 0 ]; then
            log "Successfully issued certificate for $service"
        else
            log "ERROR: Failed to issue certificate for $service"
            return 1
        fi
    done

    # Set proper permissions on host
    chmod 644 "$CERTS_DIR"/*.crt 2>/dev/null || true
    chmod 600 "$CERTS_DIR"/*.key 2>/dev/null || true

    log "All certificates issued successfully"
    return 0
}

# Update .env file with base64-encoded certificates
update_env_file() {
    local env_file=".env"

    if [ ! -f "$env_file" ]; then
        log "WARNING: .env file not found, creating from .env.example"
        if [ -f ".env.example" ]; then
            cp ".env.example" "$env_file"
        else
            touch "$env_file"
        fi
    fi

    log "Updating .env file with APISIX certificates..."

    local apisix_cert_b64
    local apisix_key_b64

    apisix_cert_b64=$(base64 -w 0 "$CERTS_DIR/apisix.crt")
    apisix_key_b64=$(base64 -w 0 "$CERTS_DIR/apisix.key")

    # Update or add APISIX_CLIENT_CERT
    if grep -q "^APISIX_CLIENT_CERT=" "$env_file"; then
        sed -i "s|^APISIX_CLIENT_CERT=.*|APISIX_CLIENT_CERT=\"$apisix_cert_b64\"|" "$env_file"
    else
        echo "APISIX_CLIENT_CERT=\"$apisix_cert_b64\"" >> "$env_file"
    fi

    # Update or add APISIX_CLIENT_KEY
    if grep -q "^APISIX_CLIENT_KEY=" "$env_file"; then
        sed -i "s|^APISIX_CLIENT_KEY=.*|APISIX_CLIENT_KEY=\"$apisix_key_b64\"|" "$env_file"
    else
        echo "APISIX_CLIENT_KEY=\"$apisix_key_b64\"" >> "$env_file"
    fi

    log "Updated .env file with new certificates"
}

# Main function
main() {
    log "Starting step-ca initialization..."

    # Check if we're in the project directory
    if [ ! -f "docker-compose.yaml" ]; then
        log "ERROR: Must run from project root directory"
        exit 1
    fi

    wait_for_step_ca || exit 1
    bootstrap_ca || exit 1
    issue_initial_certificates || exit 1
    update_env_file || exit 1

    log ""
    log "=========================================="
    log "step-ca initialization completed successfully!"
    log "=========================================="
    log ""
    log "Certificates issued:"
    for service in "${SERVICES[@]}"; do
        log "  - $CERTS_DIR/${service}.crt (expires in ${CERT_VALIDITY_HOURS}h)"
    done
    log ""
    log "Next steps:"
    log "  1. Restart services to pick up new certificates:"
    log "     podman compose restart service_a service_b openfga apisix"
    log ""
    log "  2. Start the step-renewer for automatic rotation:"
    log "     podman compose up -d step-renewer"
    log ""
    log "  3. Monitor renewal logs:"
    log "     podman compose logs -f step-renewer"
}

main "$@"
