// =============================================================================
// Application Entry Point — Dispatch Service
// This file contains only boilerplate bootstrapping code.
// All business logic is in server.go for better testability.
// =============================================================================

package main

import (
	"log"
	"net/http"
)

func main() {
	config := Config{
		Port:        getEnv("PORT", "8080"),
		ServiceName: getEnv("SERVICE_NAME", "dispatch-service"),
		Version:     getEnv("VERSION", "1.0.0"),
	}

	mux := setupRouter(config)

	// Wrap mux with metrics middleware
	handler := metricsMiddleware(mux)

	log.Printf("Starting %s on port %s", config.ServiceName, config.Port)
	if err := http.ListenAndServe(":"+config.Port, handler); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
