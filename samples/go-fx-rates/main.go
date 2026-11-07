package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type conversionResult struct {
	From            string `json:"from"`
	To              string `json:"to"`
	ConvertedAmount string `json:"converted_amount"`
	INR             string `json:"inr"`
	RateSource      string `json:"rate_source"`
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		slog.Error("response could not be written")
	}
}

func safeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func convert(w http.ResponseWriter, r *http.Request) {
	if len(r.URL.RawQuery) > 512 {
		safeError(w, http.StatusBadRequest, "Query is too large.")
		return
	}
	slog.Info("conversion request", "route", "/convert")
	query, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil || len(query) != 3 {
		safeError(w, http.StatusBadRequest, "Provide from, to and amount exactly once.")
		return
	}
	for _, key := range []string{"from", "to", "amount"} {
		if len(query[key]) != 1 || query.Get(key) == "" {
			safeError(w, http.StatusBadRequest, "Provide from, to and amount exactly once.")
			return
		}
	}
	from := strings.ToUpper(strings.TrimSpace(query.Get("from")))
	to := strings.ToUpper(strings.TrimSpace(query.Get("to")))
	if len(from) != 3 || to != "INR" {
		safeError(w, http.StatusBadRequest, "Use a three-letter source currency and INR target.")
		return
	}
	amount, err := parseAmount(query.Get("amount"))
	if err != nil {
		safeError(w, http.StatusBadRequest, "Amount must be 0 to 100000000 with at most eight decimal places.")
		return
	}
	rate, err := syntheticRate(from)
	if err != nil {
		safeError(w, http.StatusBadRequest, "Unsupported source currency.")
		return
	}
	select {
	case <-r.Context().Done():
		safeError(w, http.StatusRequestTimeout, "Request timed out.")
		return
	default:
	}
	paise := roundedPaise(amount, rate)
	writeJSON(w, http.StatusOK, conversionResult{
		From: from, To: "INR", ConvertedAmount: moneyString(paise),
		INR: formatINR(paise), RateSource: "synthetic fixed rates; not market data",
	})
}

func handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		r = r.WithContext(ctx)
		if r.URL.Path != "/health" && r.URL.Path != "/convert" {
			safeError(w, http.StatusNotFound, "Not found.")
			return
		}
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			safeError(w, http.StatusMethodNotAllowed, "Use GET.")
			return
		}
		if r.URL.Path == "/health" {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
			return
		}
		convert(w, r)
	})
}

func serverPort() (string, error) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	value, err := strconv.Atoi(port)
	if err != nil || value < 1 || value > 65535 {
		return "", errors.New("PORT must be between 1 and 65535")
	}
	return strconv.Itoa(value), nil
}

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	port, err := serverPort()
	if err != nil {
		slog.Error("invalid PORT configuration")
		os.Exit(1)
	}
	if len(os.Args) == 2 && os.Args[1] == "-healthcheck" {
		client := &http.Client{Timeout: 2 * time.Second}
		response, err := client.Get("http://127.0.0.1:" + port + "/health")
		if err != nil {
			os.Exit(1)
		}
		response.Body.Close()
		if response.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		return
	}
	server := &http.Server{
		Addr: ":" + port, Handler: handler(),
		ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second,
		WriteTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second,
		MaxHeaderBytes: 8192,
	}
	slog.Info("synthetic FX service listening", "port", port)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("HTTP server stopped unexpectedly")
		os.Exit(1)
	}
}
