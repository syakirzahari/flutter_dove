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

  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
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
