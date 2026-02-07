# =============================================================================
# Multi-stage Dockerfile for Dispatch Service
# Stage 1: Build | Stage 2: Runtime (minimal image)
# =============================================================================

# --- Build Stage ---
FROM golang:1.25.7-alpine AS builder

WORKDIR /app

# Copy dependency files first (cache optimization)
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o dispatch-service .

# --- Runtime Stage ---
FROM alpine:3.20

# Security: Run as non-root user
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D appuser

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/dispatch-service .

# Set ownership
RUN chown -R appuser:appgroup /app

USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the application
ENTRYPOINT ["./dispatch-service"]
