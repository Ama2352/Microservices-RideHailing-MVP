package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestHealthEndpoint tests the /health endpoint
func TestHealthEndpoint(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "notification-service",
		Version:     "1.0.0",
	}

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	mux := setupRouter(config)
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response HealthResponse
	if err := json.NewDecoder(w.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if response.Service != "notification-service" {
		t.Errorf("Expected service 'notification-service', got '%s'", response.Service)
	}

	if response.Status != "healthy" {
		t.Errorf("Expected status 'healthy', got '%s'", response.Status)
	}
}

// TestMetricsEndpoint tests the /metrics endpoint
func TestMetricsEndpoint(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "notification-service",
		Version:     "1.0.0",
	}

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	w := httptest.NewRecorder()

	mux := setupRouter(config)
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	body := w.Body.String()
	if body == "" {
		t.Error("Metrics should not be empty")
	}

	// Verify Prometheus metrics format
	if !strings.Contains(body, "go_goroutines") {
		t.Error("Expected Go runtime metrics in output")
	}
}

// TestMetricsMiddleware tests that middleware records metrics
func TestMetricsMiddleware(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "notification-service",
		Version:     "1.0.0",
	}

	mux := setupRouter(config)
	handler := metricsMiddleware(mux)

	// Make request through middleware
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	// Check that metrics were recorded
	metricsReq := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	metricsW := httptest.NewRecorder()
	handler.ServeHTTP(metricsW, metricsReq)

	metricsBody := metricsW.Body.String()
	if !strings.Contains(metricsBody, "http_requests_total") {
		t.Error("Middleware should record http_requests_total")
	}

	if !strings.Contains(metricsBody, "http_request_duration_seconds") {
		t.Error("Middleware should record http_request_duration_seconds")
	}
}

// TestStatusWriter tests the custom ResponseWriter wrapper
func TestStatusWriter(t *testing.T) {
	w := httptest.NewRecorder()
	sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}

	// Test WriteHeader
	sw.WriteHeader(http.StatusNotFound)
	if sw.status != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d", sw.status)
	}

	// Test default status is preserved
	w2 := httptest.NewRecorder()
	sw2 := &statusWriter{ResponseWriter: w2, status: http.StatusOK}
	sw2.Write([]byte("test"))
	if sw2.status != http.StatusOK {
		t.Errorf("Expected default status 200, got %d", sw2.status)
	}
}

// TestGetEnv tests the environment variable helper
func TestGetEnv(t *testing.T) {
	// Test with default value
	result := getEnv("NONEXISTENT_VAR", "default")
	if result != "default" {
		t.Errorf("Expected 'default', got '%s'", result)
	}

	// Test with set value
	t.Setenv("TEST_VAR", "test_value")
	result = getEnv("TEST_VAR", "default")
	if result != "test_value" {
		t.Errorf("Expected 'test_value', got '%s'", result)
	}
}


