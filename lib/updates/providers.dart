import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import 'data_source.dart';
import 'network.dart';

final dioProvider = Provider<Dio>((ref) {
  return createDioClient();
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  );
});

final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  throw UnimplementedError(
    'quranRepositoryProvider must be overridden in ProviderScope',
  );
});

final dataSourceProvider = Provider<QuranDataSource>((ref) {
  return const BundledDataSource();
});
