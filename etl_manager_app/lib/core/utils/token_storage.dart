import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _nameKey = 'manager_name';
  static const _emailKey = 'manager_email';
  static const _roleKey = 'user_role';
  static const _zoneKey = 'user_zone';
  static const _outletKey = 'user_outlet_id';

  // In-memory cache of the auth token. The Dio interceptor reads the token on
  // EVERY request; hitting the Keychain/Keystore each time adds noticeable
  // latency (a few ms, more on cold Android). Cache it after the first read so
  // subsequent requests are instant.
  static String? _cachedToken;
  static bool _tokenLoaded = false;

  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    _tokenLoaded = true;
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    if (_tokenLoaded) return _cachedToken;
    _cachedToken = await _storage.read(key: _tokenKey);
    _tokenLoaded = true;
    return _cachedToken;
  }

  static Future<void> saveManagerInfo(String name, String email) async {
    await _storage.write(key: _nameKey, value: name);
    await _storage.write(key: _emailKey, value: email);
  }

  static Future<void> saveRole(String role) async =>
      await _storage.write(key: _roleKey, value: role);

  static Future<void> saveZone(String? zone) async {
    if (zone != null) await _storage.write(key: _zoneKey, value: zone);
  }

  static Future<void> saveOutletId(String? outletId) async {
    if (outletId != null) {
      await _storage.write(key: _outletKey, value: outletId);
    }
  }

  static Future<String?> getOutletId() async =>
      await _storage.read(key: _outletKey);

  static Future<String?> getManagerName() async =>
      await _storage.read(key: _nameKey);

  static Future<String?> getManagerEmail() async =>
      await _storage.read(key: _emailKey);

  static Future<String?> getRole() async => await _storage.read(key: _roleKey);

  static Future<String?> getZone() async => await _storage.read(key: _zoneKey);

  // ✅ New
  static Future<bool> isStaff() async {
    final role = await _storage.read(key: _roleKey);
    return role?.toLowerCase() == 'staff';
  }

  static Future<void> clearAll() async {
    _cachedToken = null;
    _tokenLoaded = false;
    await _storage.deleteAll();
  }
}
