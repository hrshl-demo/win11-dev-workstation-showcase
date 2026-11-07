package showcase.ifsc;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class IfscControllerTest {
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new IfscController(new IfscService())).build();
    }

    @ParameterizedTest
    @ValueSource(strings = {"ABCD0123456", "abcd0123456", " abcd0123456 "})
    void returnsNormalizedValidation(String code) throws Exception {
        mvc.perform(get("/ifsc/{code}", code))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("ABCD0123456"))
                .andExpect(jsonPath("$.valid").value(true))
                .andExpect(jsonPath("$.bankCode").value("ABCD"))
                .andExpect(jsonPath("$.branchCode").value("123456"))
                .andExpect(jsonPath("$.reason", containsString("not verified")));
    }

    @ParameterizedTest
    @ValueSource(strings = {"ABCD1123456", "ABC0123456"})
    void returnsInvalidFormatAsValidationResult(String code) throws Exception {
        mvc.perform(get("/ifsc/{code}", code))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(code))
                .andExpect(jsonPath("$.valid").value(false))
                .andExpect(jsonPath("$.bankCode").value(nullValue()))
                .andExpect(jsonPath("$.branchCode").value(nullValue()))
                .andExpect(jsonPath("$.reason", containsString("Expected 11 characters")));
    }

    @Test
    void reportsHealth() throws Exception {
        mvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ok"));
    }
}
