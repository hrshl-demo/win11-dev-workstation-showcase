package showcase.ifsc;

import java.util.Locale;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;

@Service
public class IfscService {
    private static final Pattern FORMAT = Pattern.compile("^[A-Z]{4}0[A-Z0-9]{6}$");

    public IfscResult validate(String input) {
        String code = input == null ? "" : input.trim().toUpperCase(Locale.ROOT);
        if (!FORMAT.matcher(code).matches()) {
            return new IfscResult(code, false, null, null,
                    "Expected 11 characters: four letters, 0, then six letters or digits.");
        }
        return new IfscResult(code, true, code.substring(0, 4), code.substring(5),
                "Valid IFSC format; bank and branch existence are not verified.");
    }
}
