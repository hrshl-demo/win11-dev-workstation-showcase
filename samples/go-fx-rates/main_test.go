package main

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestEndpoints(t *testing.T) {
	tests := []struct {
		name, method, target string
		status               int
		inr                  string
	}{
		{"health", "GET", "/health", 200, ""},
		{"USD", "GET", "/convert?from=USD&to=INR&amount=100", 200, "₹8,800.00"},
		{"normalize", "GET", "/convert?from=%20usd%20&to=inr&amount=100", 200, "₹8,800.00"},
		{"unknown", "GET", "/convert?from=ZZZ&to=INR&amount=100", 400, ""},
		{"negative", "GET", "/convert?from=USD&to=INR&amount=-1", 400, ""},
		{"too-large", "GET", "/convert?from=USD&to=INR&amount=100000001", 400, ""},
		{"bad-target", "GET", "/convert?from=USD&to=EUR&amount=1", 400, ""},
		{"missing", "GET", "/convert?from=USD&to=INR", 400, ""},
		{"empty", "GET", "/convert?from=USD&to=INR&amount=", 400, ""},
		{"duplicate", "GET", "/convert?from=USD&to=INR&amount=1&amount=2", 400, ""},
		{"extra", "GET", "/convert?from=USD&to=INR&amount=1&x=2", 400, ""},
		{"invalid-escape", "GET", "/convert?from=USD&to=INR&amount=%ZZ", 400, ""},
		{"method", "POST", "/convert?from=USD&to=INR&amount=1", 405, ""},
		{"health-method", "POST", "/health", 405, ""},
		{"not-found", "GET", "/no-such-resource", 404, ""},
		{"oversized", "GET", "/convert?from=USD&to=INR&amount=" + strings.Repeat("1", 513), 400, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			response := httptest.NewRecorder()
			handler().ServeHTTP(response, httptest.NewRequest(tt.method, tt.target, nil))
			if response.Code != tt.status {
				t.Fatalf("got %d, want %d: %s", response.Code, tt.status, response.Body.String())
			}
			var payload map[string]any
			if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
				t.Fatal(err)
			}
			if tt.inr != "" {
				if payload["inr"] != tt.inr || payload["converted_amount"] != "8800.00" {
					t.Fatalf("unexpected conversion: %v", payload)
				}
				for _, value := range payload {
					if _, ok := value.(string); !ok {
						t.Fatal("JSON monetary fields must be strings")
					}
				}
				if !strings.Contains(payload["rate_source"].(string), "not market data") {
					t.Fatal("synthetic rate label missing")
				}
			}
			if tt.name == "health" && payload["status"] != "ok" {
				t.Fatal("health status missing")
			}
		})
	}
}

func TestCanceledRequest(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	request := httptest.NewRequest("GET", "/convert?from=USD&to=INR&amount=1", nil).WithContext(ctx)
	response := httptest.NewRecorder()
	handler().ServeHTTP(response, request)
	if response.Code != http.StatusRequestTimeout {
		t.Fatalf("got %d, want 408", response.Code)
	}
}

func TestPortConfiguration(t *testing.T) {
	for _, tt := range []struct {
		input, want string
		valid       bool
	}{
		{"", "8080", true}, {"8081", "8081", true}, {"1", "1", true},
		{"65535", "65535", true}, {"0", "", false}, {"65536", "", false},
		{"invalid", "", false},
	} {
		t.Run(tt.input, func(t *testing.T) {
			t.Setenv("PORT", tt.input)
			port, err := serverPort()
			if (err == nil) != tt.valid || port != tt.want {
				t.Fatalf("port %q, error %v", port, err)
			}

			func TestConversionLogsExcludeQueryValues(t *testing.T) {
				var output bytes.Buffer
				original := slog.Default()
				slog.SetDefault(slog.New(slog.NewJSONHandler(&output, nil)))
				t.Cleanup(func() { slog.SetDefault(original) })
				for _, target := range []string{
					"/convert?from=USD&to=INR&amount=12345.67890123",
					"/convert?from=ZZZ&to=INR&amount=12345.67890123",
					"/convert?from=USD&to=INR&amount=1&synthetic=SYN-QUERY-PRIVATE",
				} {
					handler().ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", target, nil))
				}
				for _, supplied := range []string{"12345.67890123", "SYN-QUERY-PRIVATE", "from=", "USD", "ZZZ"} {
					if strings.Contains(output.String(), supplied) {
						t.Fatalf("logs contain supplied query data %q", supplied)
					}
				}
				if strings.TrimSpace(output.String()) == "" {
					t.Fatal("expected safe diagnostics")
				}
				for _, line := range strings.Split(strings.TrimSpace(output.String()), "\n") {
					var record map[string]any
					if err := json.Unmarshal([]byte(line), &record); err != nil {
						t.Fatal(err)
					}
					if record["route"] != "/convert" {
						t.Fatal("safe route diagnostic missing")
					}
				}
			}

			func TestUnknownCurrencyErrorIsSafe(t *testing.T) {
				response := httptest.NewRecorder()
				handler().ServeHTTP(response, httptest.NewRequest("GET", "/convert?from=ZZZ&to=INR&amount=100", nil))
				if response.Code != http.StatusBadRequest {
					t.Fatalf("got %d, want 400", response.Code)
				}
				var payload map[string]string
				if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
					t.Fatal(err)
				}
				if payload["error"] != "Unsupported source currency." {
					t.Fatalf("unexpected public error: %v", payload)
				}
				for _, internal := range []string{"synthetic rate table", "no INR entry", "ZZZ"} {
					if strings.Contains(response.Body.String(), internal) {
						t.Fatalf("response leaks %q", internal)
					}
				}
			}
		})
	}
}
