import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persists a stable, per-install device identifier.
///
/// The backend upserts devices by `device_id` (see `DeviceController::store`
/// in `ost-push`), so this only needs to be stable for the app install, not
/// necessarily tied to hardware — a persisted UUID avoids the extra native
/// permissions that reading a true hardware identifier would require.
class DoveDeviceIdStore {
  static const _prefsKey = 'flutter_dove.device_id';
  static const _uuid = Uuid();

  /// Returns the persisted device id, or generates and persists a new UUID
  /// v4 if none exists yet.
  ///
  /// Pass [deviceId] to override the persisted value with a caller-supplied
  /// id (e.g. one derived from the host app's own user/account system)
  /// instead of the generated UUID; it is persisted the same way so it stays
  /// stable across subsequent calls that omit it.
  Future<String> getOrCreate({String? deviceId}) async {
    final prefs = await SharedPreferences.getInstance();

    if (deviceId != null && deviceId.isNotEmpty) {
      await prefs.setString(_prefsKey, deviceId);
      return deviceId;
    }

    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _uuid.v4();
    await prefs.setString(_prefsKey, generated);
    return generated;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
