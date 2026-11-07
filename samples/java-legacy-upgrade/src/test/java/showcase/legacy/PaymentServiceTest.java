package showcase.legacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.NullSource;
import org.junit.jupiter.params.provider.ValueSource;

class PaymentServiceTest {
    private final PaymentService service = new PaymentService();

    static PaymentService.PaymentRequest request(String amount) {
        PaymentService.PaymentRequest request = new PaymentService.PaymentRequest();
        request.setSourceAccount("SYN-ACCOUNT-001");
        request.setBeneficiaryIfsc("ABCD0123456");
        request.setAmount(amount == null ? null : new BigDecimal(amount));
        return request;
    }

    @Test
    void simulatesPaymentWithCappedFeeAndIndianGrouping() {
        PaymentService.PaymentResult result = service.simulate(request("250000.00"));
        assertEquals("SIMULATED", result.getStatus());
        assertEquals("INR", result.getCurrency());
        assertEquals(new BigDecimal("50.00"), result.getFee());
        assertEquals(new BigDecimal("250050.00"), result.getTotalDebit());
        assertEquals("₹2,50,000.00", result.getAmountInr());
        assertEquals("₹2,50,050.00", result.getTotalDebitInr());
    }

    @Test
    void roundsFeeHalfUpWithoutFloatingPoint() {
        PaymentService.PaymentResult result = service.simulate(request("1005.00"));
        assertEquals(new BigDecimal("1.01"), result.getFee());
        assertEquals(new BigDecimal("1006.01"), result.getTotalDebit());
    }

    @Test
    void acceptsAmountBoundariesAndGeneratesDistinctSyntheticReferences() {
        assertEquals(new BigDecimal("0.01"), service.simulate(request("0.01")).getAmount());
        assertEquals(new BigDecimal("50.00"), service.simulate(request("10000000.00")).getFee());
        assertNotEquals(service.simulate(request("1")).getReference(),
                service.simulate(request("1")).getReference());
    }

    @ParameterizedTest
    @NullSource
    @ValueSource(strings = {"0", "-1", "0.001", "1.001", "1.000", "10000000.01"})
    void rejectsInvalidAmounts(String amount) {
        assertThrows(IllegalArgumentException.class, () -> service.simulate(request(amount)));
    }

    @Test
    void rejectsInvalidAccountAndIfscAndMissingRequest() {
        PaymentService.PaymentRequest request = request("100");
        request.setSourceAccount("NOT-A-SYNTHETIC-ALIAS");
        assertThrows(IllegalArgumentException.class, () -> service.simulate(request));
        request.setSourceAccount("SYN-ACCOUNT-001");
        request.setBeneficiaryIfsc("ABCD1123456");
        assertThrows(IllegalArgumentException.class, () -> service.simulate(request));
        assertThrows(IllegalArgumentException.class, () -> service.simulate(null));
    }

    @ParameterizedTest
    @CsvSource({"2500000, '₹25,00,000.00'", "123456789.5, '₹12,34,56,789.50'",
            "100000, '₹1,00,000.00'", "999, '₹999.00'", "-1234567.8, '-₹12,34,567.80'", "0, '₹0.00'"})
    void formatsIndianRupees(String input, String expected) {
        assertEquals(expected, PaymentService.formatInr(new BigDecimal(input)));
    }
}
