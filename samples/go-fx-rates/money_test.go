package main

import "testing"

func TestSyntheticConversions(t *testing.T) {
	tests := []struct {
		name, amount, currency, expected string
	}{
		{"USD", "100", "USD", "₹8,800.00"},
		{"EUR", "100", "EUR", "₹10,200.00"},
		{"GBP", "100", "GBP", "₹11,700.00"},
		{"zero", "0", "USD", "₹0.00"},
		{"half-up", "0.000625", "USD", "₹0.06"},
		{"below-half", "0.00062499", "USD", "₹0.05"},
		{"lakh", "1250", "USD", "₹1,10,000.00"},
		{"maximum", "100000000", "GBP", "₹11,70,00,00,000.00"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			amount, err := parseAmount(tt.amount)
			if err != nil {
				t.Fatal(err)
			}
			rate, err := syntheticRate(tt.currency)
			if err != nil {
				t.Fatal(err)
			}
			if got := formatINR(roundedPaise(amount, rate)); got != tt.expected {
				t.Fatalf("got %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestInvalidAmounts(t *testing.T) {
	for _, amount := range []string{
		"", "-1", "NaN", "Infinity", "1e9", "100000000.00000001",
		"1.000000001", ".5", " 1", "1/2", "1.", "99999999999999999999999999999999999999999",
	} {
		t.Run(amount, func(t *testing.T) {
			if _, err := parseAmount(amount); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}
}

func TestFormatting(t *testing.T) {
	for _, tt := range []struct {
		paise int64
		want  string
	}{
		{250000000, "₹25,00,000.00"},
		{12345678950, "₹12,34,56,789.50"},
		{10000000, "₹1,00,000.00"},
		{99900, "₹999.00"},
		{-123456780, "-₹12,34,567.80"},
		{0, "₹0.00"},
	} {
		if got := formatINR(tt.paise); got != tt.want {
			t.Errorf("got %q, want %q", got, tt.want)
		}
	}
}

func TestUnknownCurrency(t *testing.T) {
	if _, err := syntheticRate("ZZZ"); err == nil {
		t.Fatal("expected unknown currency error")
	}
}
