import 'package:noetec/service/settings_service.dart';

class InMemorySettingsService implements ISettingsService {
  final _store = <String, dynamic>{};

  @override
  Future<String?> getString(String key) async => _store[key] as String?;

  @override
  Future<void> setString(String key, String value) async => _store[key] = value;

  @override
  Future<List<String>> getStringList(String key) async =>
      (_store[key] as List<String>?) ?? [];

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _store[key] = List<String>.from(value);
}
