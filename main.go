package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"strings"

	"github.com/golang-jwt/jwt/v5" // Librería para manejar JWT
	pb "github.com/ravillarreal/demo/proto"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
)

type server struct {
	pb.UnimplementedUserServiceServer
}

// Función auxiliar para extraer el "sub" sin verificar la firma
// (Asumiendo que APISIX ya verificó la firma antes de pasar la petición)
func getSubjectFromJWT(authHeader string) (string, error) {
	// 1. Quitar el prefijo "Bearer "
	tokenString := strings.TrimPrefix(authHeader, "Bearer ")
	if tokenString == authHeader {
		return "", fmt.Errorf("formato de token inválido")
	}

	// 2. Parsear el token sin validar firma (Inseguro si no hay un Proxy/Gateway antes)
	token, _, err := new(jwt.Parser).ParseUnverified(tokenString, jwt.MapClaims{})
	if err != nil {
		return "", err
	}

	// 3. Extraer el claim "sub"
	if claims, ok := token.Claims.(jwt.MapClaims); ok {
		if sub, ok := claims["sub"].(string); ok {
			return sub, nil
		}
	}

	return "", fmt.Errorf("claim 'sub' no encontrado")
}

func (s *server) GetUserInfo(ctx context.Context, in *pb.UserRequest) (*pb.UserResponse, error) {
	md, _ := metadata.FromIncomingContext(ctx)
	userID := "unknown"

	// Obtener el header Authorization
	if vals := md.Get("authorization"); len(vals) > 0 {
		authHeader := vals[0]

		// Extraer el 'sub' del JWT
		sub, err := getSubjectFromJWT(authHeader)
		if err != nil {
			log.Printf("Error decodificando JWT: %v", err)
		} else {
			userID = sub
		}
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

// ... resto del archivo (main) se mantiene igual

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
