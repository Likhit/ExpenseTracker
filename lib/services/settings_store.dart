import 'package:sembast/sembast.dart';

import 'app_settings.dart';

/// Persists a single [AppSettings] record to a sembast database, mirroring the
/// `ViewStore` pattern: the caller owns the [Database] (file-backed in
/// production, in-memory in tests), keeping this layer independent of the
/// sembast factory choice.
///
/// There is exactly one record (key [_key]); [load] returns defaults when it
/// has never been written.
class SettingsStore {
  final Database _db;
  final _store = stringMapStoreFactory.store('settings');
  static const _key = 'app';

  SettingsStore(this._db);

  /// The persisted settings, or `const AppSettings()` if none were ever saved.
  Future<AppSettings> load() async {
    final record = await _store.record(_key).get(_db);
    if (record == null) return const AppSettings();
    return AppSettings.fromJson(record.cast<String, Object?>());
  }

  /// Overwrites the single settings record with [settings].
  Future<void> save(AppSettings settings) =>
      _store.record(_key).put(_db, settings.toJson());
}
