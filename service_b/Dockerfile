# Stage 1: Build
FROM golang:1.25.5-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# Stage 2: Runtime
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/main /
EXPOSE 50052
CMD ["/main"]