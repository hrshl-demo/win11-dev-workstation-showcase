package showcase.ifsc;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class IfscApplication {
    public static void main(String[] args) {
        if (args.length == 1 && "--healthcheck".equals(args[0])) {
            try {
                String port = System.getenv().getOrDefault("PORT", "8080");
                HttpRequest request = HttpRequest.newBuilder(
                        URI.create("http://127.0.0.1:" + port + "/health"))
                        .timeout(Duration.ofSeconds(2)).GET().build();
                try (HttpClient client = HttpClient.newBuilder()
                        .connectTimeout(Duration.ofSeconds(2)).build()) {
                    int status = client.send(request, HttpResponse.BodyHandlers.discarding())
                            .statusCode();
                    System.exit(status == 200 ? 0 : 1);
                }
            } catch (Exception exception) {
                System.exit(1);
            }
            return;
        }
        SpringApplication.run(IfscApplication.class, args);
    }
}
