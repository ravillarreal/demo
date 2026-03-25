package main

import (
	"context"
	"fmt"
	"log"
	"net"

	pb "github.com/ravillarreal/proto-registry/gen/go/user/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/reflection"
)

type server struct {
	pb.UnimplementedUserServiceServer
	client pb.UserServiceClient
}

// GetUserInfo en Service B actúa como proxy hacia Service A
func (s *server) GetUserInfo(ctx context.Context, in *pb.UserRequest) (*pb.UserResponse, error) {
	// 1. Extraer metadata (headers) que vienen de la llamada original al Service B
	md, ok := metadata.FromIncomingContext(ctx)

	fmt.Println("Metadata recibida: ", md)
	if !ok {
		md = metadata.New(nil)
	}

	// 2. Inyectar la metadata en el contexto de salida hacia Service A
	outCtx := metadata.NewOutgoingContext(ctx, md)

	log.Printf("Service B: Redirigiendo petición de usuario %s a Service A", in.Id)

	// 3. Llamar al Service A
	return s.client.GetUserInfo(outCtx, in)
}

// func loadTLSCredentials(isServer bool) credentials.TransportCredentials {
// 	// Cargamos certificados (asumiendo que Service B tiene sus propios certs o usa los mismos)
// 	certFile := "certs/service_b.crt"
// 	keyFile := "certs/service_b.key"
// 	caFile := "certs/ca.crt"

// 	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
// 	if err != nil {
// 		log.Fatalf("No se pudo cargar el par de llaves: %v", err)
// 	}

// 	ca, err := ioutil.ReadFile(caFile)
// 	if err != nil {
// 		log.Fatalf("No se pudo leer la CA: %v", err)
// 	}

// 	capool := x509.NewCertPool()
// 	if !capool.AppendCertsFromPEM(ca) {
// 		log.Fatal("Fallo al agregar CA al pool")
// 	}

// 	tlsConfig := &tls.Config{
// 		MinVersion:   tls.VersionTLS13,
// 		Certificates: []tls.Certificate{cert},
// 		RootCAs:      capool,
// 		ClientCAs:    nil,
// 	}

// 	if isServer {
// 		// Aceptar solo clientes firmados por nuestra CA
// 		tlsConfig.ClientCAs = capool
// 		tlsConfig.ClientAuth = tls.RequireAndVerifyClientCert
// 	} else {
// 		// Validar el nombre del servidor de Service A frente al SAN del certificado
// 		tlsConfig.ServerName = "service_a"
// 	}

// 	return credentials.NewTLS(tlsConfig)
// }

func main() {
	// --- CONFIGURACIÓN DEL CLIENTE (Hacia Service A) ---
	// Service A corre en 50051
	conn, err := grpc.NewClient("service_a:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("No se pudo conectar con Service A: %v", err)
	}
	defer conn.Close()

	userClient := pb.NewUserServiceClient(conn)

	// --- CONFIGURACIÓN DEL SERVIDOR (Service B) ---
	lis, err := net.Listen("tcp", ":50052")
	if err != nil {
		log.Fatalf("Error en listener: %v", err)
	}

	s := grpc.NewServer()

	// Registramos el servidor pasando el cliente de Service A
	pb.RegisterUserServiceServer(s, &server{client: userClient})
	reflection.Register(s)

	log.Println("Service B (Proxy) corriendo en :50052...")
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Error al servir: %v", err)
	}
}
