package main

import (
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"strings"
)

var amountPattern = regexp.MustCompile(`^[0-9]+(?:\.[0-9]{1,8})?$`)

const maxAmount = 100000000

func parseAmount(text string) (*big.Rat, error) {
	if len(text) == 0 || len(text) > 40 || !amountPattern.MatchString(text) {
		return nil, errors.New("amount must be non-negative decimal text with at most eight fractional digits")
	}
	amount, ok := new(big.Rat).SetString(text)
	if !ok || amount.Sign() < 0 || amount.Cmp(new(big.Rat).SetInt64(maxAmount)) > 0 {
		return nil, errors.New("amount must be between 0 and 100000000")
	}
	return amount, nil
}

func syntheticRate(currency string) (int64, error) {
	switch currency {
	case "USD":
		return 88, nil
	case "EUR":
		return 102, nil
	case "GBP":
		return 117, nil
	default:
		return 0, fmt.Errorf("synthetic rate table: no INR entry for currency %q", currency)
	}
}

func roundedPaise(amount *big.Rat, rate int64) int64 {
	scaled := new(big.Rat).Mul(amount, new(big.Rat).SetInt64(rate*100))
	quotient, remainder := new(big.Int), new(big.Int)
	quotient.QuoRem(scaled.Num(), scaled.Denom(), remainder)
	if new(big.Int).Lsh(remainder, 1).Cmp(scaled.Denom()) >= 0 {
		quotient.Add(quotient, big.NewInt(1))
	}
	return quotient.Int64()
}

func moneyString(paise int64) string {
	sign := ""
	if paise < 0 {
		sign = "-"
		paise = -paise
	}
	return fmt.Sprintf("%s%d.%02d", sign, paise/100, paise%100)
}

func formatINR(paise int64) string {
	value := moneyString(paise)
	sign := ""
	if strings.HasPrefix(value, "-") {
		sign, value = "-", value[1:]
	}
	parts := strings.SplitN(value, ".", 2)
	whole := parts[0]
	if len(whole) > 3 {
		head, tail := whole[:len(whole)-3], whole[len(whole)-3:]
		groups := []string{tail}
		for len(head) > 0 {
			start := len(head) - 2
			if start < 0 {
				start = 0
			}
			groups = append([]string{head[start:]}, groups...)
			head = head[:start]
		}
		whole = strings.Join(groups, ",")
	}
	return sign + "₹" + whole + "." + parts[1]
}
