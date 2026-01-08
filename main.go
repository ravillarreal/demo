package main

import (
	"context"
	"log"
	"net"

	pb "github.com/ravillarreal/demo/proto" // Asegúrate de generar tus .pb.go
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
)

type server struct {
	pb.UnimplementedUserServiceServer
}

func (s *server) GetUserInfo(ctx context.Context, in *pb.UserRequest) (*pb.UserResponse, error) {
	// Extraemos headers inyectados por APISIX (AuthN y AuthZ)
	md, _ := metadata.FromIncomingContext(ctx)

	// Zitadel suele enviar el subject en "x-user-id" o similar tras la validación JWT
	userID := "unknown"

	log.Println("Metadata recibida:", md)
	if vals := md.Get("X-User-ID"); len(vals) > 0 {
		userID = vals[0]
	}

	// El Tenant ID es crítico en B2B para filtrar la DB
	tenantID := "default-tenant"
	if vals := md.Get("x-tenant-id"); len(vals) > 0 {
		tenantID = vals[0]
	}

	log.Printf("Petición autorizada para Usuario: %s en Tenant: %s", userID, tenantID)

	return &pb.UserResponse{
		Message:  "¡Hola usuario " + userID + " desde el backend gRPC de 2026!",
		TenantId: tenantID,
	}, nil
}

func main() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("Error al escuchar: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterUserServiceServer(s, &server{})

	// Habilitar reflection es vital para que APISIX pueda leer los métodos gRPC
	reflection.Register(s)

	log.Println("Servidor gRPC corriendo en :50051...")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Error al servir: %v", err)
	}
}
