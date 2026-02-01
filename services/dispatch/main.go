package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

// Config holds service configuration
type Config struct {
	Port        string
	ServiceName string
	Version     string
}

// HealthResponse represents the health check response
type HealthResponse struct {
	Status    string `json:"status"`
	Service   string `json:"service"`
	Version   string `json:"version"`
	Timestamp string `json:"timestamp"`
}

func main() {
	config := Config{
		Port:        getEnv("PORT", "8080"),
		ServiceName: getEnv("SERVICE_NAME", "dispatch-service"),
		Version:     getEnv("VERSION", "1.0.0"),
	}

	mux := http.NewServeMux()

	// Health check endpoint
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		response := HealthResponse{
			Status:    "unhealthy",
			Service:   config.ServiceName,
			Version:   config.Version,
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(response)
	})

	// Readiness probe
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	})

	// Root endpoint
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"message": "Dispatch Service - Ride-Hailing MVP",
			"version": config.Version,
		})
	})

	log.Printf("Starting %s on port %s", config.ServiceName, config.Port)
	if err := http.ListenAndServe(":"+config.Port, mux); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
