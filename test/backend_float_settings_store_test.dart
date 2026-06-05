import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_flutter/data/local/app_database.dart';
import 'package:wallet_flutter/data/local/app_local_cache.dart';
import 'package:wallet_flutter/services/backend_float/backend_float_settings_store.dart';

void main() {
  test('persists module float enabled flag', () async {
    final cache = AppLocalCache(AppDatabase.forTesting());
    addTearDown(cache.close);
    final store = BackendFloatSettingsStore(cache);

    expect(await store.readEnabled('tron_energy_rental'), isNull);

    await store.writeEnabled('tron_energy_rental', false);
    expect(await store.readEnabled('tron_energy_rental'), isFalse);

    await store.writeEnabled('tron_energy_rental', true);
    expect(await store.readEnabled('tron_energy_rental'), isTrue);
  });
}
