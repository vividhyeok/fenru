import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCredentials implements CredentialStore {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: 'fenru.$key');
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: 'fenru.$key', value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: 'fenru.$key');
}
