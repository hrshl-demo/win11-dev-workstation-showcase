FROM eclipse-temurin:11-jdk@sha256:810d03ef723872693a38e5c1367cc88a0bee58edcf06a2ab868ccc048888db73 AS build
WORKDIR /workspace
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN chmod +x mvnw
COPY src src
RUN ./mvnw -B verify

FROM eclipse-temurin:11-jre@sha256:5dd0f12260b837ce636299e4fc0a10c7c70ed879d1f162470da6badd6f8f733d
WORKDIR /app
COPY --from=build --chown=10001:10001 /workspace/target/app.jar app.jar
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD ["java", "-jar", "app.jar", "--healthcheck"]
ENTRYPOINT ["java", "-jar", "app.jar"]
