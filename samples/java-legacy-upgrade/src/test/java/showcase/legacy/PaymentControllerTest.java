package showcase.legacy;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(PaymentController.class)
@Import(PaymentService.class)
class PaymentControllerTest {
    @Autowired
    private MockMvc mvc;

    @Test
    void simulatesSyntheticPayment() throws Exception {
        mvc.perform(post("/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sourceAccount\":\"SYN-ACCOUNT-001\","
                                + "\"beneficiaryIfsc\":\"ABCD0123456\",\"amount\":250000.00}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SIMULATED"))
                .andExpect(jsonPath("$.reference", startsWith("SYN-")))
                .andExpect(jsonPath("$.currency").value("INR"))
                .andExpect(jsonPath("$.amount").value(250000.00))
                .andExpect(jsonPath("$.fee").value(50.00))
                .andExpect(jsonPath("$.totalDebit").value(250050.00))
                .andExpect(jsonPath("$.amountInr").value("₹2,50,000.00"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "-1", "10000000.01", "1.001", "1.000", "null"})
    void rejectsInvalidAmountsWithSafeMessage(String amount) throws Exception {
        mvc.perform(post("/payments").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"sourceAccount\":\"SYN-ACCOUNT-001\","
                                + "\"beneficiaryIfsc\":\"ABCD0123456\",\"amount\":" + amount + "}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.reason").value("Invalid synthetic payment request."));
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{", "{\"sourceAccount\":\"INVALID\",\"beneficiaryIfsc\":\"ABCD0123456\",\"amount\":100}",
            "{\"sourceAccount\":\"SYN-ACCOUNT-001\",\"beneficiaryIfsc\":\"ABCD1123456\",\"amount\":100}"})
    void rejectsInvalidBodyAndRoutingDetails(String body) throws Exception {
        mvc.perform(post("/payments").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.reason").value("Invalid synthetic payment request."));
    }

    @Test
    void reportsHealth() throws Exception {
        mvc.perform(get("/health")).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ok"));
    }
}
