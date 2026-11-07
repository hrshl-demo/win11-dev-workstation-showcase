package showcase.ifsc;

public record IfscResult(String code, boolean valid, String bankCode, String branchCode, String reason) {
}
