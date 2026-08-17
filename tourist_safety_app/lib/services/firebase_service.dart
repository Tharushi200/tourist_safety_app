import 'package:firebase_database/firebase_database.dart';

/// FirebaseService — handles all Realtime Database operations for IoT devices,
/// tourist group persistence, guide group history, and user device preferences.
class FirebaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // =========================================================================
  // DEVICE PAIRING
  // =========================================================================

  /// Links an IoT hardware device to a user and optionally a group.
  /// Firebase path: devices/{deviceId}
  Future<void> pairHardwareDevice({
    required String deviceId,
    required String userId,
    required String userName,
    String groupId = '',
  }) async {
    try {
      await _db.ref('devices/$deviceId').set({
        'deviceId': deviceId,
        'userId': userId,
        'userName': userName,
        'groupId': groupId,
        'pairedAt': ServerValue.timestamp,
        'status': 'online',
      });
    } catch (e) {
      print('FirebaseService pairHardwareDevice error: $e');
    }
  }

  /// Updates only the groupId field of a paired device.
  /// Called when tourist joins a group after pairing.
  Future<void> updateDeviceGroup(String deviceId, String groupId) async {
    try {
      await _db.ref('devices/$deviceId').update({
        'groupId': groupId,
      });
    } catch (e) {
      print('FirebaseService updateDeviceGroup error: $e');
    }
  }

  /// Clears all user/group info from the device node — marks it as unpaired.
  /// Called on logout or mode switch to Phone GPS.
  Future<void> unpairHardwareDevice(String deviceId) async {
    try {
      await _db.ref('devices/$deviceId').update({
        'userId': '',
        'userName': '',
        'groupId': '',
        'status': 'unpaired',
      });
    } catch (e) {
      print('FirebaseService unpairHardwareDevice error: $e');
    }
  }

  /// Returns the current status string of the device (e.g. "online", "unpaired").
  Future<String> getDeviceStatus(String deviceId) async {
    try {
      final snapshot = await _db.ref('devices/$deviceId/status').get();
      if (snapshot.exists) {
        return snapshot.value?.toString() ?? 'unknown';
      }
    } catch (e) {
      print('FirebaseService getDeviceStatus error: $e');
    }
    return 'unknown';
  }

  // =========================================================================
  // USER DEVICE PREFERENCES (replaces SharedPreferences)
  // =========================================================================

  /// Saves the user's hardware device preference to RTDB.
  /// Avoids SharedPreferences (which requires Kotlin 2.3+ on Android).
  /// Firebase path: userPrefs/{userId}
  Future<void> saveUserDevicePrefs({
    required String userId,
    required bool useHardwareDevice,
    required String pairedDeviceId,
  }) async {
    try {
      await _db.ref('userPrefs/$userId').update({
        'useHardwareDevice': useHardwareDevice,
        'pairedDeviceId': pairedDeviceId,
      });
    } catch (e) {
      print('FirebaseService saveUserDevicePrefs error: $e');
    }
  }

  /// Loads the user's hardware device preference from RTDB.
  /// Returns a map with 'useHardwareDevice' (bool) and 'pairedDeviceId' (String).
  Future<Map<String, dynamic>> loadUserDevicePrefs(String userId) async {
    try {
      final snapshot = await _db.ref('userPrefs/$userId').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return {
          'useHardwareDevice': data['useHardwareDevice'] as bool? ?? false,
          'pairedDeviceId': data['pairedDeviceId'] as String? ?? '',
        };
      }
    } catch (e) {
      print('FirebaseService loadUserDevicePrefs error: $e');
    }
    return {'useHardwareDevice': false, 'pairedDeviceId': ''};
  }

  // =========================================================================
  // TOURIST GROUP PERSISTENCE
  // =========================================================================

  /// Saves the current groupId for the tourist so it can be auto-restored
  /// when the app is re-opened.
  /// Firebase path: users/{userId}/currentGroupId
  Future<void> saveTouristGroup(String userId, String groupId) async {
    try {
      await _db.ref('users/$userId').update({
        'currentGroupId': groupId,
      });
    } catch (e) {
      print('FirebaseService saveTouristGroup error: $e');
    }
  }

  /// Reads the last joined groupId for the tourist.
  /// Returns empty string if none is saved.
  Future<String> getTouristGroup(String userId) async {
    try {
      final snapshot = await _db.ref('users/$userId/currentGroupId').get();
      if (snapshot.exists && snapshot.value != null) {
        return snapshot.value.toString();
      }
    } catch (e) {
      print('FirebaseService getTouristGroup error: $e');
    }
    return '';
  }

  // =========================================================================
  // GUIDE GROUP HISTORY
  // =========================================================================

  /// Saves a created group to the guide's history in RTDB.
  /// Firebase path: users/{userId}/groups/{groupId}
  Future<void> saveGroupToUser(
    String userId,
    String groupId,
    String groupName,
  ) async {
    try {
      await _db.ref('users/$userId/groups/$groupId').set({
        'groupId': groupId,
        'groupName': groupName,
        'createdAt': ServerValue.timestamp,
      });
    } catch (e) {
      print('FirebaseService saveGroupToUser error: $e');
    }
  }

  /// Returns the list of groups created by the guide, sorted newest first.
  Future<List<Map<String, dynamic>>> getUserGroups(String userId) async {
    try {
      final snapshot = await _db.ref('users/$userId/groups').get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final raw = Map<String, dynamic>.from(snapshot.value as Map);
      final groups = raw.entries.map((e) {
        final val = Map<String, dynamic>.from(e.value as Map);
        return val;
      }).toList();

      // Sort newest first by createdAt timestamp
      groups.sort((a, b) {
        final aTs = (a['createdAt'] as num?) ?? 0;
        final bTs = (b['createdAt'] as num?) ?? 0;
        return bTs.compareTo(aTs);
      });

      return groups;
    } catch (e) {
      print('FirebaseService getUserGroups error: $e');
    }
    return [];
  }
}
