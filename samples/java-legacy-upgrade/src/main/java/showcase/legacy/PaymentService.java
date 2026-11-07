package showcase.legacy;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.UUID;
import java.util.regex.Pattern;
import javax.validation.constraints.DecimalMax;
import javax.validation.constraints.DecimalMin;
import javax.validation.constraints.Digits;
import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;
import org.springframework.stereotype.Service;

@Service
public class PaymentService {
    private static final Pattern ACCOUNT = Pattern.compile("^SYN-ACCOUNT-[0-9]{3}$");
    private static final Pattern IFSC = Pattern.compile("^[A-Z]{4}0[A-Z0-9]{6}$");
    private static final BigDecimal MAX_AMOUNT = new BigDecimal("10000000.00");
    private static final BigDecimal FEE_RATE = new BigDecimal("0.001");
    private static final BigDecimal MAX_FEE = new BigDecimal("50.00");

    public PaymentResult simulate(PaymentRequest request) {
        if (request == null || request.getSourceAccount() == null
                || !ACCOUNT.matcher(request.getSourceAccount()).matches()
                || request.getBeneficiaryIfsc() == null
                || !IFSC.matcher(request.getBeneficiaryIfsc()).matches()
                || request.getAmount() == null
                || request.getAmount().compareTo(new BigDecimal("0.01")) < 0
                || request.getAmount().compareTo(MAX_AMOUNT) > 0
                || request.getAmount().scale() > 2) {
            throw new IllegalArgumentException("Invalid synthetic payment request.");
        }
        BigDecimal amount = request.getAmount().setScale(2, RoundingMode.HALF_UP);
        BigDecimal fee = amount.multiply(FEE_RATE).min(MAX_FEE).setScale(2, RoundingMode.HALF_UP);
        return new PaymentResult("SYN-" + UUID.randomUUID(), amount, fee, amount.add(fee));
    }

    static String formatInr(BigDecimal value) {
        String[] parts = value.abs().setScale(2, RoundingMode.HALF_UP).toPlainString().split("\\.");
        String digits = parts[0];
        StringBuilder grouped = new StringBuilder(digits.substring(Math.max(0, digits.length() - 3)));
        for (int end = digits.length() - 3; end > 0; end -= 2) {
            grouped.insert(0, digits.substring(Math.max(0, end - 2), end) + ",");
        }
        return (value.signum() < 0 ? "-₹" : "₹") + grouped + "." + parts[1];
    }

    public static class PaymentRequest {
        @NotBlank
        @javax.validation.constraints.Pattern(regexp = "^SYN-ACCOUNT-[0-9]{3}$")
        private String sourceAccount;

        @NotBlank
        @javax.validation.constraints.Pattern(regexp = "^[A-Z]{4}0[A-Z0-9]{6}$")
        private String beneficiaryIfsc;

        @NotNull
        @DecimalMin("0.01")
        @DecimalMax("10000000.00")
        @Digits(integer = 8, fraction = 2)
        private BigDecimal amount;

        public String getSourceAccount() {
            return sourceAccount;
        }

        public void setSourceAccount(String sourceAccount) {
            this.sourceAccount = sourceAccount;
        }

        public String getBeneficiaryIfsc() {
            return beneficiaryIfsc;
        }

        public void setBeneficiaryIfsc(String beneficiaryIfsc) {
            this.beneficiaryIfsc = beneficiaryIfsc;
        }

        public BigDecimal getAmount() {
            return amount;
        }

        public void setAmount(BigDecimal amount) {
            this.amount = amount;
        }
    }

    public static class PaymentResult {
        private final String reference;
        private final BigDecimal amount;
        private final BigDecimal fee;
        private final BigDecimal totalDebit;

        public PaymentResult(String reference, BigDecimal amount, BigDecimal fee, BigDecimal totalDebit) {
            this.reference = reference;
            this.amount = amount;
            this.fee = fee;
            this.totalDebit = totalDebit;
        }

        public String getReference() {
            return reference;
        }

        public String getStatus() {
            return "SIMULATED";
        }

        public String getCurrency() {
            return "INR";
        }

        public BigDecimal getAmount() {
            return amount;
        }

        public BigDecimal getFee() {
            return fee;
        }

        public BigDecimal getTotalDebit() {
            return totalDebit;
        }

        public String getAmountInr() {
            return formatInr(amount);
        }

        public String getFeeInr() {
            return formatInr(fee);
        }

        public String getTotalDebitInr() {
            return formatInr(totalDebit);
        }
    }
}
