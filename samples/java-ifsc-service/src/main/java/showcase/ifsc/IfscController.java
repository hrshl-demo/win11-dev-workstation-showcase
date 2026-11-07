package showcase.ifsc;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class IfscController {
    private final IfscService service;

    public IfscController(IfscService service) {
        this.service = service;
    }

    @GetMapping("/ifsc/{code}")
    public IfscResult validate(@PathVariable String code) {
        return service.validate(code);
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }
}
