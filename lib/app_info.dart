/// Canonical, file-system-safe app identifier.
///
/// Used as the subdirectory name for app-private storage (the JSONL files
/// under the user's documents directory). Kept separate from the user-facing
/// display name (`'Expense Tracker'`, in `app.dart`) and the package name in
/// `pubspec.yaml` so the storage path stays stable if either of those change.
const String appName = 'expense_tracker';
