package showcase.ifsc;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

class IfscServiceTest {
    private final IfscService service = new IfscService();

    @ParameterizedTest
    @ValueSource(strings = {"ABCD0123456", "abcd0123456", "  abcd0123456  "})
    void normalizesValidCodes(String input) {
        IfscResult result = service.validate(input);
        assertTrue(result.valid());
        assertEquals("ABCD0123456", result.code());
        assertEquals("ABCD", result.bankCode());
        assertEquals("123456", result.branchCode());
        assertTrue(result.reason().contains("not verified"));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"ABCD1123456", "ABC0123456", "ABCD01234567", "ABCD012-456", "ABCD0１２３４５６", " "})
    void rejectsInvalidCodesWithoutPartialBankInformation(String input) {
        IfscResult result = service.validate(input);
        assertFalse(result.valid());
        assertNull(result.bankCode());
        assertNull(result.branchCode());
        assertTrue(result.reason().startsWith("Expected 11 characters"));
    }

    @Test
    void allowsAlphanumericBranchCode() {
        IfscResult result = service.validate("BANK0A1B2C3");
        assertTrue(result.valid());
        assertEquals("A1B2C3", result.branchCode());
    }
}
