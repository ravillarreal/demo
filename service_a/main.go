package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"log"
	"net"
	"os"

	pb "github.com/ravillarreal/proto-registry/gen/go/user/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
)

type server struct {
	pb.UnimplementedUserServiceServer
}

func (s *server) GetUserInfo(ctx context.Context, in *pb.UserRequest) (*pb.UserResponse, error) {
	md, _ := metadata.FromIncomingContext(ctx)
	fmt.Println("Metadata recibida: ", md)
	userID := "unknown-user"

	if vals := md.Get("x-user-id"); len(vals) > 0 {
		userID = vals[0]
	}

	// El Tenant ID se mantiene igual desde el header inyectado
	tenantID := "default-tenant"
	if vals := md.Get("x-tenant-id"); len(vals) > 0 {
		tenantID = vals[0]
	}

	log.Printf("Petición procesada -> User (sub): %s | Tenant: %s", userID, tenantID)

	return &pb.UserResponse{
		Message:  "¡Hola usuario " + userID + "!",
		TenantId: tenantID,
	}, nil
}

func listDirs(path string) {
	entries, err := os.ReadDir(path)
	if err != nil {
		log.Fatalf("Error leyendo el directorio: %v", err)
	}

	log.Println("Contenido del directorio", path)
	for _, entry := range entries {
		log.Println(" -", entry.Name())
	}
}

func main() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Error al escuchar: %v", err)
	}

	fmt.Println("Listando directorios para debug:")

	listDirs("./certs")

	// Cargar el certificado del servidor y la llave privada
	serverCert, _ := tls.LoadX509KeyPair("certs/service_a.crt", "certs/service_a.key")

	// Cargar la CA para validar el certificado que enviará APISIX
	certPool := x509.NewCertPool()
	ca, _ := os.ReadFile("certs/ca.crt")
	certPool.AppendCertsFromPEM(ca)

	creds := credentials.NewTLS(&tls.Config{
		ClientAuth:   tls.RequireAndVerifyClientCert, // Fuerza mTLS
		ClientCAs:    certPool,
		Certificates: []tls.Certificate{serverCert},
	})

	s := grpc.NewServer(grpc.Creds(creds))
	pb.RegisterUserServiceServer(s, &server{})

	// Habilitar reflection es vital para que APISIX pueda leer los métodos gRPC
	reflection.Register(s)

	log.Println("Servidor gRPC corriendo en :50051...")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Error al servir: %v", err)
	}
}
