import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

/// LocationService — handles phone GPS tracking.
/// In hardware (IoT) mode, all phone GPS operations are skipped because
/// the ESP8266 device pushes GPS data directly to Firebase.
class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<Position>? _positionSubscription;
  LatLng _lastKnownPosition = const LatLng(7.8731, 80.7718);

  LatLng get lastKnownPosition => _lastKnownPosition;

  // =========================================================================
  // PERMISSIONS
  // =========================================================================

  /// Requests location permission.
  /// In hardware mode this is skipped — no phone GPS needed.
  Future<bool> requestPermissions({bool isHardwareDevice = false}) async {
    if (isHardwareDevice) return true; // hardware device handles its own GPS

    final status = await Permission.location.request();
    return status.isGranted;
  }

  // =========================================================================
  // START TRACKING
  // =========================================================================

  /// Starts streaming phone GPS to Firestore `groups/{groupCode}/locations/{userId}`.
  /// In hardware mode the stream is never started — the ESP8266 writes directly.
  ///
  /// [onPositionUpdate] is called with each new LatLng so the UI can re-center the map.
  Future<void> startTracking({
    required String groupCode,
    required String userId,
    required String userName,
    bool isHardwareDevice = false,
    void Function(LatLng position)? onPositionUpdate,
  }) async {
    // Cancel any existing subscription first
    await stopTracking(isHardwareDevice: isHardwareDevice);

    if (isHardwareDevice) {
      // Hardware mode: phone GPS is intentionally skipped.
      // The ESP8266 writes to Firebase Realtime Database independently.
      return;
    }

    final granted = await requestPermissions();
    if (!granted) return;

    // Get an initial fix quickly so the map centres immediately
    try {
      final initPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _lastKnownPosition = LatLng(initPos.latitude, initPos.longitude);
      onPositionUpdate?.call(_lastKnownPosition);
    } catch (_) {}

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // only emit when moved ≥ 10 m
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) async {
        _lastKnownPosition = LatLng(pos.latitude, pos.longitude);
        onPositionUpdate?.call(_lastKnownPosition);

        // Simulated battery level (replace with battery_plus if needed)
        final int battery = 88 - (DateTime.now().minute % 12);

        await _firestore
            .collection('groups')
            .doc(groupCode)
            .collection('locations')
            .doc(userId)
            .set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
          'batteryPercent': battery,
          'name': userName,
          'role': 'tourist',
        });
      },
    );
  }

  // =========================================================================
  // STOP TRACKING
  // =========================================================================

  /// Cancels the GPS stream.
  /// In hardware mode the location document in Firestore is intentionally NOT
  /// removed because the ESP8266 owns that document; let the device handle it.
  Future<void> stopTracking({
    bool isHardwareDevice = false,
    String? groupCode,
    String? userId,
  }) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (!isHardwareDevice && groupCode != null && userId != null) {
      // Optionally remove stale location doc when using phone GPS
      try {
        await _firestore
            .collection('groups')
            .doc(groupCode)
            .collection('locations')
            .doc(userId)
            .delete();
      } catch (_) {}
    }
  }

  // =========================================================================
  // SEPARATION CHECK
  // =========================================================================

  /// Calculates the distance (in metres) between the tourist's current position
  /// and the guide's position read from Firestore.
  /// Works in both phone-GPS and hardware mode because it reads from Firestore.
  Future<double?> getDistanceFromGuide({
    required String groupCode,
    required String userId,
  }) async {
    try {
      // Get tourist position (phone or hardware — both write to Firestore)
      final touristDoc = await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('locations')
          .doc(userId)
          .get();

      if (!touristDoc.exists) return null;
      final tData = touristDoc.data()!;
      final double tLat = (tData['lat'] as num).toDouble();
      final double tLng = (tData['lng'] as num).toDouble();

      // Find guide document (role == 'guide')
      final locSnapshot = await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('locations')
          .get();

      for (final doc in locSnapshot.docs) {
        final data = doc.data();
        if ((data['role'] as String?) == 'guide') {
          final double gLat = (data['lat'] as num).toDouble();
          final double gLng = (data['lng'] as num).toDouble();
          return Geolocator.distanceBetween(tLat, tLng, gLat, gLng);
        }
      }
    } catch (_) {}
    return null;
  }
}
