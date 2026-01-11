Generar código Go desde Protobuf
================================

Este proyecto usa Protocol Buffers y gRPC. Para generar los archivos Go desde `user.proto` use el siguiente comando:

```bash
protoc --include_imports --descriptor_set_out=./proto/user.pb \
    --go_out=./proto --go_opt=paths=source_relative \
	--go-grpc_out=./proto --go-grpc_opt=paths=source_relative \
	user.proto
```
Ejecutar el comando en la raíz del repositorio (donde está `user.proto`).

# Para iniciar:

1. Ejecutar scripts

```
cd scripts
./generate_certs.sh
./deploy-model.sh
./run.sh
```
