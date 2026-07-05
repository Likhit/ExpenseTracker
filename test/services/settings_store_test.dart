import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:expense_tracker/services/app_settings.dart';
import 'package:expense_tracker/services/settings_store.dart';

void main() {
  Future<SettingsStore> freshStore() async {
    final db = await newDatabaseFactoryMemory().openDatabase('settings.db');
    return SettingsStore(db);
  }

  group('SettingsStore', () {
    test('load returns defaults when nothing was ever saved', () async {
      final store = await freshStore();
      final settings = await store.load();
      expect(settings.syncFolder, isNull);
      expect(settings.defaultCurrencyCode, isNull);
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.onboardingComplete, isFalse);
    });

    test('round-trips every field', () async {
      final store = await freshStore();
      const written = AppSettings(
        syncFolder: '/home/user/Drive/expenses',
        defaultCurrencyCode: 'EUR',
        themeMode: AppThemeMode.dark,
        onboardingComplete: true,
      );
      await store.save(written);
      final read = await store.load();
      expect(read, written);
    });

    test('save overwrites the single record', () async {
      final store = await freshStore();
      await store.save(const AppSettings(defaultCurrencyCode: 'USD'));
      await store.save(const AppSettings(defaultCurrencyCode: 'GBP'));
      final read = await store.load();
      expect(read.defaultCurrencyCode, 'GBP');
    });

    test('copyWith can clear a nullable field back to null', () {
      const base = AppSettings(syncFolder: '/tmp/x', defaultCurrencyCode: 'USD');
      final cleared = base.copyWith(syncFolder: null);
      expect(cleared.syncFolder, isNull);
      // Other fields untouched.
      expect(cleared.defaultCurrencyCode, 'USD');
    });
  });
}
