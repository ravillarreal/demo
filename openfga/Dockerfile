# Extraer el binario fga de la imagen oficial
FROM openfga/cli:latest AS cli

FROM alpine:3.21
RUN apk add --no-cache jq

COPY --from=cli /fga /usr/local/bin/fga

WORKDIR /openfga
COPY model.fga .
COPY model.fga.yaml .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["sh", "/openfga/entrypoint.sh"]
