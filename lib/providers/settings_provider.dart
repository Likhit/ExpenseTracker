import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sembast/sembast_io.dart';

import '../app_info.dart';
import '../services/app_settings.dart';
import '../services/settings_store.dart';

part 'settings_provider.g.dart';

/// The [SettingsStore] for the app, backed by a file-based sembast database
/// under the app-support directory. `keepAlive` because settings live for the
/// whole session; tests override this with an in-memory store.
@Riverpod(keepAlive: true)
Future<SettingsStore> settingsStore(Ref ref) async {
  final dir = await getApplicationSupportDirectory();
  final appDir = Directory('${dir.path}/$appName');
  await appDir.create(recursive: true);
  final db = await databaseFactoryIo.openDatabase('${appDir.path}/settings.db');
  ref.onDispose(db.close);
  return SettingsStore(db);
}

/// The current [AppSettings], loaded once from the [settingsStoreProvider] and
/// mutated through the methods below. Every mutation write-throughs to the
/// store, then updates [state] so listeners rebuild.
///
/// `keepAlive` — the ledger and the theme both depend on it for the session.
@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  Future<AppSettings> build() async {
    final store = await ref.watch(settingsStoreProvider.future);
    return store.load();
  }

  Future<void> _update(AppSettings next) async {
    final store = await ref.read(settingsStoreProvider.future);
    await store.save(next);
    state = AsyncData(next);
  }

  AppSettings get _current => state.value ?? const AppSettings();

  /// Point the ledger at [folder] (null → local-only default dir). Callers that
  /// change this must expect [ledgerProvider] to rebuild against the new path.
  Future<void> setSyncFolder(String? folder) =>
      _update(_current.copyWith(syncFolder: folder));

  Future<void> setDefaultCurrency(String? code) =>
      _update(_current.copyWith(defaultCurrencyCode: code));

  Future<void> setThemeMode(AppThemeMode mode) =>
      _update(_current.copyWith(themeMode: mode));

  Future<void> completeOnboarding() =>
      _update(_current.copyWith(onboardingComplete: true));
}
