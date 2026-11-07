---
applyTo: "**/*.java"
---
# Java

For java-ifsc-service use Java 25, Spring Boot 4, JUnit 5, records and constructor injection.
Validate and normalize inputs in a service; test controllers in-process. Use BigDecimal with explicit rounding for money.
Run the sample's Maven wrapper (`.\mvnw.cmd -B verify` on Windows).
Exception: java-legacy-upgrade deliberately stays Java 11 / Spring Boot 2.7 with its compatible tests until the user invokes modernization. Do not upgrade it manually or include it in the current-service CI matrix.
