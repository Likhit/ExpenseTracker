import 'validation_result.dart';

/// Implemented by entities that can validate themselves before being
/// persisted. `LedgerService.save` runs `validate()` automatically when
/// the entity opts into this interface; if validation fails, no write
/// happens and the [ValidationResult] is returned to the caller.
abstract interface class Validatable {
  ValidationResult validate();
}
