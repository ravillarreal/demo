#!/bin/bash
set -e

# This script works with both Docker and Podman via DOCKER_HOST environment variable
# Podman provides a Docker-compatible API, so docker CLI commands work transparently

# Configuration
STEP_CA_URL="${STEP_CA_URL:-https://step-ca:9000}"
RENEWAL_THRESHOLD_HOURS="${RENEWAL_THRESHOLD_HOURS:-6}"
CERT_VALIDITY_HOURS="${CERT_VALIDITY_HOURS:-24}"
CERTS_DIR="/certs"
STEP_CA_CONFIG="/step-ca-config"
ENV_FILE="/env/.env"

# Services that need certificates
SERVICES=("apisix" "openfga" "service_a" "service_b")

# Restart order for rolling restarts
RESTART_ORDER=("service_a" "service_b" "openfga" "apisix")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if a certificate needs renewal
needs_renewal() {
    local cert_file="$1"

    if [ ! -f "$cert_file" ]; then
        log "Certificate $cert_file does not exist"
        return 0
    fi

    # Get certificate expiry date in seconds since epoch
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)

    if [ -z "$expiry_date" ]; then
        log "Could not read expiry from $cert_file"
        return 0
    fi

    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)

    if [ -z "$expiry_epoch" ]; then
        log "Could not parse expiry date: $expiry_date"
        return 0
    fi

    local now_epoch
    now_epoch=$(date +%s)

    local threshold_seconds=$((RENEWAL_THRESHOLD_HOURS * 3600))
    local time_until_expiry=$((expiry_epoch - now_epoch))

    if [ "$time_until_expiry" -lt "$threshold_seconds" ]; then
        log "Certificate $cert_file expires in $((time_until_expiry / 3600)) hours (threshold: ${RENEWAL_THRESHOLD_HOURS}h)"
        return 0
    fi

    log "Certificate $cert_file is valid for $((time_until_expiry / 3600)) more hours"
    return 1
}

# Get step-ca provisioner password
get_ca_password() {
    if [ -f "$STEP_CA_CONFIG/secrets/password" ]; then
        cat "$STEP_CA_CONFIG/secrets/password"
    else
        echo "${STEP_CA_PASSWORD:-changeme}"
    fi
}

# Issue a new certificate for a service
issue_certificate() {
    local service_name="$1"
    local cert_file="$CERTS_DIR/${service_name}.crt"
    local key_file="$CERTS_DIR/${service_name}.key"

    log "Issuing new certificate for $service_name"

    # Get CA fingerprint
    local fingerprint
    fingerprint=$(step certificate fingerprint "$CERTS_DIR/ca.crt" 2>/dev/null || echo "")

    if [ -z "$fingerprint" ]; then
        log "ERROR: Could not get CA fingerprint"
        return 1
    fi

    local password
    password=$(get_ca_password)

    # Issue certificate with SANs for the service
    if ! step ca certificate "$service_name" "$cert_file" "$key_file" \
        --ca-url="$STEP_CA_URL" \
        --root="$CERTS_DIR/ca.crt" \
        --provisioner="admin" \
        --provisioner-password-file=<(echo "$password") \
        --san="$service_name" \
        --san="localhost" \
        --not-after="${CERT_VALIDITY_HOURS}h" \
        --force 2>/dev/null; then
        log "ERROR: Failed to issue certificate for $service_name"
        return 1
    fi

    # Set proper permissions
    chmod 644 "$cert_file"
    chmod 600 "$key_file"

    log "Successfully issued certificate for $service_name"
    return 0
}

# Update .env file with base64-encoded certificates for APISIX
update_env_file() {
    if [ ! -f "$ENV_FILE" ]; then
        log "ENV file not found at $ENV_FILE, skipping env update"
        return 0
    fi

    log "Updating .env file with new APISIX certificates"

    local apisix_cert_b64
    local apisix_key_b64

    apisix_cert_b64=$(base64 -w 0 "$CERTS_DIR/apisix.crt")
    apisix_key_b64=$(base64 -w 0 "$CERTS_DIR/apisix.key")

    # Create a temporary file for sed operations
    local tmp_env="/tmp/env_update_$$"
    cp "$ENV_FILE" "$tmp_env"

    # Update or add APISIX_CLIENT_CERT
    if grep -q "^APISIX_CLIENT_CERT=" "$tmp_env"; then
        sed -i "s|^APISIX_CLIENT_CERT=.*|APISIX_CLIENT_CERT=\"$apisix_cert_b64\"|" "$tmp_env"
    else
        echo "APISIX_CLIENT_CERT=\"$apisix_cert_b64\"" >> "$tmp_env"
    fi

    # Update or add APISIX_CLIENT_KEY
    if grep -q "^APISIX_CLIENT_KEY=" "$tmp_env"; then
        sed -i "s|^APISIX_CLIENT_KEY=.*|APISIX_CLIENT_KEY=\"$apisix_key_b64\"|" "$tmp_env"
    else
        echo "APISIX_CLIENT_KEY=\"$apisix_key_b64\"" >> "$tmp_env"
    fi

    mv "$tmp_env" "$ENV_FILE"
    log "Updated .env file with new certificates"
}

# Perform rolling restart of services
rolling_restart() {
    log "Starting rolling restart of services"

    for service in "${RESTART_ORDER[@]}"; do
        log "Restarting $service..."

        # Get the container name (works with both Docker Compose and Podman Compose naming)
        # Matches containers with names containing the service name (e.g., demo_service_a_1, demo-service_a-1)
        local container
        container=$(docker ps --filter "name=${service}" --format "{{.Names}}" | grep -E "(^|[-_])${service}([-_]|$)" | head -1)

        if [ -z "$container" ]; then
            # Fallback: try exact service name match
            container=$(docker ps --filter "name=${service}" --format "{{.Names}}" | head -1)
        fi

        if [ -z "$container" ]; then
            log "WARNING: Container for $service not found, skipping"
            continue
        fi

        if docker restart "$container" 2>/dev/null; then
            log "Successfully restarted $container"
            # Wait for service to be healthy before continuing
            sleep 5
        else
            log "WARNING: Failed to restart $container"
        fi
    done

    log "Rolling restart completed"
}

# Main renewal logic
main() {
    log "Starting certificate renewal check"

    local certs_renewed=false

    # Check each service certificate
    for service in "${SERVICES[@]}"; do
        local cert_file="$CERTS_DIR/${service}.crt"

        if needs_renewal "$cert_file"; then
            if issue_certificate "$service"; then
                certs_renewed=true
            fi
        fi
    done

    # If any certificates were renewed, update env and restart services
    if [ "$certs_renewed" = true ]; then
        log "Certificates were renewed, updating environment and restarting services"
        update_env_file
        rolling_restart
    else
        log "No certificates need renewal"
    fi

    log "Certificate renewal check completed"
}

# Run main function
main "$@"
