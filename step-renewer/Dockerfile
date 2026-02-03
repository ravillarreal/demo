FROM smallstep/step-cli:latest
# Switch to root to install packages
USER root
# docker-cli works with Podman's Docker-compatible API socket
RUN apk add --no-cache bash curl docker-cli openssl jq
COPY renew.sh /usr/local/bin/renew.sh
RUN chmod +x /usr/local/bin/renew.sh
# Switch back to step user for runtime
USER step
# DOCKER_HOST is set via environment in compose file to point to Podman socket
CMD ["sh", "-c", "while true; do /usr/local/bin/renew.sh; sleep 3600; done"]
