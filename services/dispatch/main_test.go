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
		ServiceName: "dispatch-service",
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

	if response.Service != "dispatch-service" {
		t.Errorf("Expected service 'dispatch-service', got '%s'", response.Service)
	}

	if response.Status != "unhealthy" {
		t.Errorf("Expected status 'unhealthy', got '%s'", response.Status)
	}

	if response.Version != config.Version {
		t.Errorf("Expected version '%s', got '%s'", config.Version, response.Version)
	}
}

// TestReadyEndpoint tests the /ready endpoint
func TestReadyEndpoint(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "dispatch-service",
		Version:     "1.0.0",
	}

	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	w := httptest.NewRecorder()

	mux := setupRouter(config)
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	if w.Body.String() != "ready" {
		t.Errorf("Expected body 'ready', got '%s'", w.Body.String())
	}
}

// TestRootEndpoint tests the / endpoint
func TestRootEndpoint(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "dispatch-service",
		Version:     "1.0.0",
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()

	mux := setupRouter(config)
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	var response map[string]string
	if err := json.NewDecoder(w.Body).Decode(&response); err != nil {
		t.Fatalf("Failed to decode response: %v", err)
	}

	if response["message"] != "Dispatch Service - Ride-Hailing MVP" {
		t.Errorf("Expected message 'Dispatch Service - Ride-Hailing MVP', got '%s'", response["message"])
	}

	if response["version"] != config.Version {
		t.Errorf("Expected version '%s', got '%s'", config.Version, response["version"])
	}
}

// TestMetricsEndpoint tests the /metrics endpoint
func TestMetricsEndpoint(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "dispatch-service",
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
	
	// Check for Prometheus metrics format
	if body == "" {
		t.Error("Metrics should not be empty")
	}

	// Verify Go runtime metrics are present (from promhttp.Handler)
	expectedMetrics := []string{
		"go_goroutines",
		"go_memstats_alloc_bytes",
	}

	for _, metric := range expectedMetrics {
		if !strings.Contains(body, metric) {
			t.Errorf("Expected metric '%s' not found in output", metric)
		}
	}
}

// TestMetricsMiddleware tests that middleware records metrics
func TestMetricsMiddleware(t *testing.T) {
	config := Config{
		Port:        "8080",
		ServiceName: "dispatch-service",
		Version:     "1.0.0",
	}

	// Make a request through middleware to trigger metric recording
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	mux := setupRouter(config)
	handler := metricsMiddleware(mux)
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected status 200, got %d", w.Code)
	}

	// Verify metrics were recorded by checking /metrics endpoint
	metricsReq := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	metricsW := httptest.NewRecorder()
	handler.ServeHTTP(metricsW, metricsReq)

	metricsBody := metricsW.Body.String()
	if !strings.Contains(metricsBody, "http_requests_total") {
		t.Error("Middleware should record http_requests_total metric")
	}

	if !strings.Contains(metricsBody, "http_request_duration_seconds") {
		t.Error("Middleware should record http_request_duration_seconds metric")
	}
}

// TestStatusWriter tests the custom ResponseWriter wrapper
func TestStatusWriter(t *testing.T) {
	w := httptest.NewRecorder()
	sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}

	sw.WriteHeader(http.StatusNotFound)

	if sw.status != http.StatusNotFound {
		t.Errorf("Expected status 404, got %d", sw.status)
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


