/// Outcome of validating a domain operation (e.g., a transaction).
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult._(this.isValid, this.errorMessage);

  factory ValidationResult.ok() => const ValidationResult._(true, null);
  factory ValidationResult.error(String message) =>
      ValidationResult._(false, message);
}

/// Implemented by entities that can validate themselves before being
/// persisted. `LedgerService.save` runs `validate()` automatically when
/// the entity opts into this interface; if validation fails, no write
/// happens and the [ValidationResult] is returned to the caller.
abstract interface class Validatable {
  ValidationResult validate();
}
