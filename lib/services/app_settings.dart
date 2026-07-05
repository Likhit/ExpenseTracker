/// App-level user preferences, persisted independently of the ledger journal.
///
/// Kept as a plain, Flutter-free value type in the services layer (like the
/// rest of the engine) so it can be unit-tested without a widget binding. The
/// UI maps [AppThemeMode] onto Flutter's `ThemeMode`.
///
/// Nullable fields carry meaning:
/// - [syncFolder] null → local-only (JSONL lives under the default app data
///   directory); non-null → the user-picked sync folder holding the JSONL.
/// - [defaultCurrencyCode] null → no explicit default yet (entry flows fall
///   back to the first active fiat).
enum AppThemeMode { system, light, dark }

class AppSettings {
  final String? syncFolder;
  final String? defaultCurrencyCode;
  final AppThemeMode themeMode;
  final bool onboardingComplete;

  const AppSettings({
    this.syncFolder,
    this.defaultCurrencyCode,
    this.themeMode = AppThemeMode.system,
    this.onboardingComplete = false,
  });

  /// Sentinel distinguishing "leave unchanged" from "set to null" in
  /// [copyWith] for the two nullable fields.
  static const Object _unset = Object();

  AppSettings copyWith({
    Object? syncFolder = _unset,
    Object? defaultCurrencyCode = _unset,
    AppThemeMode? themeMode,
    bool? onboardingComplete,
  }) =>
      AppSettings(
        syncFolder: identical(syncFolder, _unset)
            ? this.syncFolder
            : syncFolder as String?,
        defaultCurrencyCode: identical(defaultCurrencyCode, _unset)
            ? this.defaultCurrencyCode
            : defaultCurrencyCode as String?,
        themeMode: themeMode ?? this.themeMode,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );

  Map<String, Object?> toJson() => {
        'syncFolder': syncFolder,
        'defaultCurrencyCode': defaultCurrencyCode,
        'themeMode': themeMode.name,
        'onboardingComplete': onboardingComplete,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        syncFolder: json['syncFolder'] as String?,
        defaultCurrencyCode: json['defaultCurrencyCode'] as String?,
        themeMode: AppThemeMode.values.asNameMap()[json['themeMode']] ??
            AppThemeMode.system,
        onboardingComplete: json['onboardingComplete'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.syncFolder == syncFolder &&
      other.defaultCurrencyCode == defaultCurrencyCode &&
      other.themeMode == themeMode &&
      other.onboardingComplete == onboardingComplete;

  @override
  int get hashCode =>
      Object.hash(syncFolder, defaultCurrencyCode, themeMode, onboardingComplete);
}
