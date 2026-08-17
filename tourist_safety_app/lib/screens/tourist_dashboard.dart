import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'login_screen.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';

class TouristDashboard extends StatefulWidget {
  const TouristDashboard({super.key});

  @override
  State<TouristDashboard> createState() => _TouristDashboardState();
}

class _TouristDashboardState extends State<TouristDashboard> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseService _firebaseService = FirebaseService();
  final LocationService _locationService = LocationService();

  String touristName = "";
  String joinedGroupCode = "";
  String gpsSource = "gps"; // legacy field kept for UI display
  bool isLoading = true;
  bool isJoining = false;
  bool isLeaving = false;
  bool isSendingSOS = false;

  // ── Hardware device state ──────────────────────────────────────────────
  bool _useHardwareDevice = false;
  String _pairedDeviceId = '';
  final TextEditingController _deviceIdController = TextEditingController();

  int _currentIndex = 0; // 0: Map, 1: SOS, 2: Chat

  // Controllers
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();

  // Location
  LatLng _currentTouristPosition = const LatLng(7.8731, 80.7718);
  StreamSubscription<Position>? _locationSubscription;

  // Map state
  GoogleMapController? _mapController;
  MapType _currentMapType = MapType.normal;

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();
    _loadTouristData();
  }

  @override
  void dispose() {
    _locationService.stopTracking(
      isHardwareDevice: _useHardwareDevice,
      groupCode: joinedGroupCode.isNotEmpty ? joinedGroupCode : null,
      userId: _auth.currentUser?.uid,
    );
    _deviceIdController.dispose();
    _codeController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  // =========================================================================
  // PREFS (persist hardware mode in Firebase RTDB — no SharedPreferences needed)
  // =========================================================================

  Future<void> _loadPrefs() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final prefs = await _firebaseService.loadUserDevicePrefs(uid);
    setState(() {
      _useHardwareDevice = prefs['useHardwareDevice'] as bool? ?? false;
      _pairedDeviceId = prefs['pairedDeviceId'] as String? ?? '';
    });
  }

  Future<void> _savePrefs() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firebaseService.saveUserDevicePrefs(
      userId: uid,
      useHardwareDevice: _useHardwareDevice,
      pairedDeviceId: _pairedDeviceId,
    );
  }

  // =========================================================================
  // LOAD TOURIST DATA
  // =========================================================================

  Future<void> _loadTouristData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Load persisted hardware prefs first
    await _loadPrefs();

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          touristName = data['name'] ?? "";
          joinedGroupCode = data['groupCode'] ?? "";
          gpsSource = (data.containsKey('gpsSource') && (data['gpsSource'] as String).isNotEmpty)
              ? data['gpsSource']
              : "gps";
          isLoading = false;
        });

        // Try auto-restore from RTDB if Firestore has no group
        if (joinedGroupCode.isEmpty) {
          final savedGroup = await _firebaseService.getTouristGroup(uid);
          if (savedGroup.isNotEmpty) {
            setState(() => joinedGroupCode = savedGroup);
          }
        }

        if (joinedGroupCode.isNotEmpty) {
          _startLocationSharing(joinedGroupCode);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // =========================================================================
  // DEVICE MODE DIALOG
  // =========================================================================

  void _showDeviceModeDialog() {
    bool tempHardware = _useHardwareDevice;
    _deviceIdController.text = _pairedDeviceId;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: const Color(0xFFF3F4F6),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ─────────────────────────────────────────
                    Row(
                      children: [
                        Icon(Icons.router, color: Colors.orange.shade700, size: 28),
                        const SizedBox(width: 10),
                        const Text(
                          "Device Mode",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D2129),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Choose how your location is tracked",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),

                    // ── Option 1: Phone GPS ────────────────────────────
                    _modeOption(
                      selected: !tempHardware,
                      icon: Icons.smartphone,
                      title: "Phone GPS",
                      subtitle: "Uses this phone's built-in GPS",
                      onTap: () => setDialogState(() => tempHardware = false),
                    ),
                    const SizedBox(height: 12),

                    // ── Option 2: IoT Wearable ─────────────────────────
                    _modeOption(
                      selected: tempHardware,
                      icon: Icons.developer_board,
                      title: "IoT Wearable (ESP8266)",
                      subtitle: "A hardware GPS device pushes data",
                      onTap: () => setDialogState(() => tempHardware = true),
                    ),

                    // ── Device ID field (only shown in hardware mode) ──
                    if (tempHardware) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _deviceIdController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: "Device ID (e.g. DEV-01)",
                          prefixIcon: const Icon(Icons.qr_code, color: Color(0xFF00897B)),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF00897B), width: 1.5),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Action buttons ─────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel",
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tempHardware
                                  ? Colors.orange.shade700
                                  : const Color(0xFF00897B),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _applyDeviceMode(
                                  tempHardware,
                                  _deviceIdController.text.trim().toUpperCase());
                            },
                            icon: Icon(
                              tempHardware ? Icons.link : Icons.smartphone,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: Text(
                              tempHardware ? "Link & Pair Device" : "Use Phone GPS",
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modeOption({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F2F1) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF00897B) : Colors.grey.shade300,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? const Color(0xFF00897B) : Colors.grey,
                size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selected ? const Color(0xFF00897B) : Colors.black87)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFF00897B), size: 20),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // APPLY DEVICE MODE
  // =========================================================================

  Future<void> _applyDeviceMode(bool hardware, String deviceId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // If switching away from hardware, unpair old device first
    if (!hardware && _useHardwareDevice && _pairedDeviceId.isNotEmpty) {
      await _firebaseService.unpairHardwareDevice(_pairedDeviceId);
    }

    setState(() {
      _useHardwareDevice = hardware;
      _pairedDeviceId = hardware ? deviceId : '';
      gpsSource = hardware ? 'esp8266' : 'gps';
    });

    await _savePrefs();

    // Update Firestore gpsSource for legacy support
    await _firestore.collection('users').doc(uid).update({
      'gpsSource': hardware ? 'esp8266' : 'gps',
    });

    if (hardware && deviceId.isNotEmpty) {
      // Pair the device in RTDB
      await _firebaseService.pairHardwareDevice(
        deviceId: deviceId,
        userId: uid,
        userName: touristName.isNotEmpty ? touristName : (_auth.currentUser?.email ?? 'Tourist'),
        groupId: joinedGroupCode,
      );

      // Restart tracking (will be a no-op for hardware mode)
      if (joinedGroupCode.isNotEmpty) {
        _stopLocationSharing();
        _startLocationSharing(joinedGroupCode);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("📡 Paired with device $deviceId"),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (!hardware) {
      // Switch back to phone GPS
      if (joinedGroupCode.isNotEmpty) {
        _stopLocationSharing();
        _startLocationSharing(joinedGroupCode);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📱 Switched to Phone GPS"),
          backgroundColor: Color(0xFF00897B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // =========================================================================
  // LOCATION SOURCE DIALOG (legacy — kept for backward compat)
  // =========================================================================

  void _showLocationSourceDialog() => _showDeviceModeDialog();

  // =========================================================================
  // PROFILE DIALOG
  // =========================================================================

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Color(0xFF00897B), size: 30),
            SizedBox(width: 10),
            Text("Tourist Profile", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${touristName.isNotEmpty ? touristName : 'Tourist'}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text("Email: ${_auth.currentUser?.email ?? 'N/A'}",
                style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text("Role: Tourist",
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              _useHardwareDevice
                  ? "📡 IoT Device: ${_pairedDeviceId.isNotEmpty ? _pairedDeviceId : 'Not paired'}"
                  : "📱 Location: Phone GPS",
              style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF00897B),
                  fontWeight: FontWeight.w600),
            ),
            if (joinedGroupCode.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.group, color: Color(0xFF00897B), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text("Joined Group: $joinedGroupCode",
                          style: const TextStyle(
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (joinedGroupCode.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _leaveGroup();
              },
              icon: const Icon(Icons.group_remove, color: Colors.orange, size: 18),
              label: const Text("Switch / Leave Group",
                  style: TextStyle(color: Colors.orange)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            icon: const Icon(Icons.logout, color: Colors.white, size: 18),
            label: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // JOIN GROUP
  // =========================================================================

  Future<void> _joinGroup() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a group code")),
      );
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => isJoining = true);

    try {
      final groupDoc = await _firestore.collection('groups').doc(code).get();

      if (!groupDoc.exists) {
        throw Exception("Invalid group code. Try again.");
      }

      await _firestore
          .collection('groups')
          .doc(code)
          .collection('members')
          .doc(uid)
          .set({
        'name': touristName.isNotEmpty
            ? touristName
            : (_auth.currentUser?.email ?? "Tourist"),
        'email': _auth.currentUser?.email ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('users').doc(uid).update({'groupCode': code});

      // ── Save to RTDB for auto-restore ──────────────────────────────
      await _firebaseService.saveTouristGroup(uid, code);

      // ── Sync group to hardware device if paired ────────────────────
      if (_useHardwareDevice && _pairedDeviceId.isNotEmpty) {
        await _firebaseService.updateDeviceGroup(_pairedDeviceId, code);
      }

      _codeController.clear();

      if (!mounted) return;
      setState(() {
        joinedGroupCode = code;
        isJoining = false;
        _currentIndex = 0;
      });

      _startLocationSharing(code);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Successfully joined group: $code"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isJoining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().contains("Invalid")
              ? "Invalid group code."
              : "Failed to join group. Try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =========================================================================
  // LEAVE GROUP
  // =========================================================================

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.group_remove, color: Colors.orange),
            SizedBox(width: 8),
            Text("Leave Group?"),
          ],
        ),
        content: const Text(
            "You will stop location sharing with your guide.\n\nYou can join a new group afterwards."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Leave", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => isLeaving = true);

    try {
      // Stop phone GPS
      await _locationService.stopTracking(
        isHardwareDevice: _useHardwareDevice,
        groupCode: joinedGroupCode,
        userId: uid,
      );

      // Remove from Firestore group members
      if (joinedGroupCode.isNotEmpty) {
        await _firestore
            .collection('groups')
            .doc(joinedGroupCode)
            .collection('members')
            .doc(uid)
            .delete();
      }

      // Clear groupCode in Firestore
      await _firestore.collection('users').doc(uid).update({'groupCode': ''});

      // Clear groupId in RTDB
      await _firebaseService.saveTouristGroup(uid, '');

      // Clear hardware device group
      if (_useHardwareDevice && _pairedDeviceId.isNotEmpty) {
        await _firebaseService.updateDeviceGroup(_pairedDeviceId, '');
      }

      if (!mounted) return;
      setState(() {
        joinedGroupCode = '';
        isLeaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You have left the group."),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLeaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to leave group: ${e.toString()}")),
      );
    }
  }

  // =========================================================================
  // LOCATION SHARING (phone GPS path)
  // =========================================================================

  Future<void> _startLocationSharing(String code) async {
    _stopLocationSharing();

    if (_useHardwareDevice) {
      // Hardware mode: ESP8266 handles its own GPS upload — nothing to do here.
      return;
    }

    await _locationService.startTracking(
      groupCode: code,
      userId: _auth.currentUser?.uid ?? '',
      userName: touristName.isNotEmpty
          ? touristName
          : (_auth.currentUser?.email ?? 'Tourist'),
      isHardwareDevice: false,
      onPositionUpdate: (pos) {
        if (mounted) setState(() => _currentTouristPosition = pos);
      },
    );
  }

  void _stopLocationSharing() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    // Also stop via LocationService (no-op if already cancelled)
    _locationService.stopTracking(isHardwareDevice: _useHardwareDevice);
  }

  void _showPermissionRetryDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Location Permission Required"),
        content: const Text(
            "Location permission is needed to share your position with the guide."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startLocationSharing(code);
            },
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // LOGOUT
  // =========================================================================

  Future<void> _logout() async {
    // Unpair hardware device before signing out
    if (_useHardwareDevice && _pairedDeviceId.isNotEmpty) {
      await _firebaseService.unpairHardwareDevice(_pairedDeviceId);
    }

    _stopLocationSharing();
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // =========================================================================
  // SEND SOS ALERT
  // =========================================================================

  Future<void> _sendSOSAlert() async {
    if (joinedGroupCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("You must join a group before sending an SOS.")),
      );
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => isSendingSOS = true);

    try {
      // For hardware mode, use last known position from RTDB / Firestore
      double lat = _currentTouristPosition.latitude;
      double lng = _currentTouristPosition.longitude;

      if (!_useHardwareDevice) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }

      await _firestore
          .collection('groups')
          .doc(joinedGroupCode)
          .collection('alerts')
          .add({
        'touristUid': uid,
        'touristName': touristName.isNotEmpty
            ? touristName
            : (_auth.currentUser?.email ?? "Tourist"),
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
        'status': "active",
        'source': _useHardwareDevice ? 'hardware' : 'phone',
      });

      if (!mounted) return;
      setState(() => isSendingSOS = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚨 SOS Alert Sent! Your guide has been notified."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSendingSOS = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send SOS: ${e.toString()}")),
      );
    }
  }

  // =========================================================================
  // SEND CHAT MESSAGE
  // =========================================================================

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('groups')
        .doc(joinedGroupCode)
        .collection('messages')
        .add({
      'senderUid': uid,
      'senderName': touristName.isNotEmpty
          ? touristName
          : (_auth.currentUser?.email ?? "Tourist"),
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _chatController.clear();
  }

  // =========================================================================
  // FIT MAP BOUNDS
  // =========================================================================

  void _fitGroupBounds(Set<Marker> markers) {
    if (markers.isEmpty || _mapController == null) return;

    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (var m in markers) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLng) minLng = m.position.longitude;
      if (m.position.longitude > maxLng) maxLng = m.position.longitude;
    }

    if (minLat == maxLat && minLng == maxLng) {
      _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 15));
      return;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        70.0,
      ),
    );
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          "SmartTour - Tourist",
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: false,
        actions: [
          // ── Device Mode / Pairing button ─────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.router,
                  color: _useHardwareDevice
                      ? Colors.orange.shade300
                      : Colors.white,
                ),
                tooltip: "Device Mode",
                onPressed: _showDeviceModeDialog,
              ),
              if (_useHardwareDevice)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            tooltip: "Profile",
            onPressed: _showProfileDialog,
          ),
        ],
      ),
      body: joinedGroupCode.isEmpty
          ? _buildNoJoinedGroupTab(_currentIndex)
          : _buildActiveGroupTab(_currentIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
        elevation: 8,
        indicatorColor: const Color(0xFFE0F2F1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: Color(0xFF00897B)),
            label: "Map",
          ),
          NavigationDestination(
            icon: Icon(Icons.emergency_outlined),
            selectedIcon: Icon(Icons.emergency, color: Color(0xFF00897B)),
            label: "SOS",
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat, color: Color(0xFF00897B)),
            label: "Chat",
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TABS — NO GROUP
  // =========================================================================

  Widget _buildNoJoinedGroupTab(int index) {
    if (index == 0) return _buildGroupJoinScreen();

    String tabTitle = "Tab";
    IconData tabIcon = Icons.info;
    if (index == 1) {
      tabTitle = "SOS";
      tabIcon = Icons.emergency_outlined;
    } else if (index == 2) {
      tabTitle = "Chat";
      tabIcon = Icons.chat_bubble_outline;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.teal.shade50, shape: BoxShape.circle),
              child: Icon(tabIcon, size: 48, color: const Color(0xFF00897B)),
            ),
            const SizedBox(height: 20),
            Text("No Active Group Joined",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Text(
              "Join a tour group on the Map tab to access $tabTitle.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => setState(() => _currentIndex = 0),
              icon: const Icon(Icons.group_add, color: Colors.white),
              label: const Text("Join Group",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SCREEN — GROUP JOIN
  // =========================================================================

  Widget _buildGroupJoinScreen() {
    final displayName = touristName.isNotEmpty ? touristName : "Tourist";

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Hi, $displayName!",
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D2129)),
          ),
          const SizedBox(height: 24),

          // Hardware device status banner
          if (_useHardwareDevice)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.router,
                      color: Colors.orange.shade700, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pairedDeviceId.isNotEmpty
                          ? "📡 Using IoT Device: $_pairedDeviceId"
                          : "📡 IoT Mode — no device ID set",
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline,
                    color: Color(0xFF00897B), size: 26),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    "Ask your tour guide for the group code to join.",
                    style: TextStyle(
                        color: Color(0xFF00897B),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Text(
            "Enter group code",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Color(0xFF00897B)),
            decoration: InputDecoration(
              fillColor: Colors.white,
              filled: true,
              hintText: "X X X X X X X X",
              hintStyle: TextStyle(
                  color: Colors.grey.shade300,
                  letterSpacing: 4,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              counterText: "",
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFF00897B), width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: isJoining ? null : _joinGroup,
              child: isJoining
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      "Join Group",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB ROUTING — ACTIVE GROUP
  // =========================================================================

  Widget _buildActiveGroupTab(int index) {
    switch (index) {
      case 0:
        return _buildMapTab();
      case 1:
        return _buildSOSTab();
      case 2:
        return _buildChatTab();
      default:
        return const Center(child: Text("Tab not found"));
    }
  }

  // =========================================================================
  // TAB 0 — MAP
  // =========================================================================

  Widget _buildMapTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .doc(joinedGroupCode)
          .collection('locations')
          .snapshots(),
      builder: (context, snapshot) {
        final Set<Marker> markers = {};
        final myUid = _auth.currentUser?.uid;

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            final role = data['role'] as String? ?? 'tourist';
            final name = data['name'] as String? ?? 'Unknown';
            final uid = doc.id;

            if (lat == null || lng == null) continue;

            final position = LatLng(lat, lng);
            final isGuide = role == 'guide';
            final isMe = uid == myUid;

            final hue = isGuide
                ? BitmapDescriptor.hueAzure
                : (isMe
                    ? BitmapDescriptor.hueOrange
                    : BitmapDescriptor.hueGreen);

            markers.add(Marker(
              markerId: MarkerId(uid),
              position: position,
              icon: BitmapDescriptor.defaultMarkerWithHue(hue),
              infoWindow: InfoWindow(
                title: isGuide
                    ? '🧭 Guide: $name'
                    : (isMe ? '📍 You: $name' : '🧑‍🤝‍🧑 $name'),
                snippet: isGuide ? 'Tour Leader' : 'Tourist Member',
              ),
            ));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fitGroupBounds(markers);
          });
        }

        return Stack(
          children: [
            GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                if (markers.isNotEmpty) _fitGroupBounds(markers);
              },
              initialCameraPosition: CameraPosition(
                  target: _currentTouristPosition, zoom: 15),
              mapType: _currentMapType,
              myLocationEnabled: !_useHardwareDevice,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: markers,
            ),

            // ── Top info card ──────────────────────────────────────────
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.group,
                            color: Color(0xFF00897B), size: 22),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Group: $joinedGroupCode',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Row(
                              children: [
                                Icon(
                                  _useHardwareDevice
                                      ? Icons.router
                                      : Icons.smartphone,
                                  size: 12,
                                  color: _useHardwareDevice
                                      ? Colors.orange
                                      : const Color(0xFF00897B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _useHardwareDevice
                                      ? 'IoT: $_pairedDeviceId'
                                      : 'Phone GPS',
                                  style: TextStyle(
                                      color: _useHardwareDevice
                                          ? Colors.orange
                                          : const Color(0xFF00897B),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.people,
                                  color: Color(0xFF00897B), size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${markers.length}',
                                style: const TextStyle(
                                    color: Color(0xFF00897B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.exit_to_app,
                              color: Colors.redAccent, size: 20),
                          tooltip: 'Leave Group',
                          onPressed: isLeaving ? null : _leaveGroup,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Legend ────────────────────────────────────────────────
            Positioned(
              bottom: 100,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendItem(Colors.blue[700]!, '🧭 Guide'),
                    const SizedBox(height: 4),
                    _legendItem(Colors.orange[700]!, '📍 You'),
                    const SizedBox(height: 4),
                    _legendItem(Colors.green[600]!, '🧑‍🤝‍🧑 Tourist'),
                  ],
                ),
              ),
            ),

            // ── Map control FABs ───────────────────────────────────────
            Positioned(
              bottom: 100,
              right: 12,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'tourist_recenter',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(
                            _currentTouristPosition, 16),
                      );
                    },
                    child: const Icon(Icons.my_location,
                        color: Color(0xFF00897B)),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'tourist_fit_all',
                    backgroundColor: Colors.white,
                    onPressed: () => _fitGroupBounds(markers),
                    child: const Icon(Icons.fit_screen,
                        color: Color(0xFF00897B)),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'tourist_map_type',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _currentMapType =
                            _currentMapType == MapType.normal
                                ? MapType.satellite
                                : MapType.normal;
                      });
                    },
                    child: Icon(
                      _currentMapType == MapType.normal
                          ? Icons.satellite_alt
                          : Icons.map,
                      color: const Color(0xFF00897B),
                    ),
                  ),
                ],
              ),
            ),

            if (snapshot.connectionState == ConnectionState.waiting &&
                markers.isEmpty)
              const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF00897B)),
              ),
          ],
        );
      },
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // =========================================================================
  // TAB 1 — SOS
  // =========================================================================

  Widget _buildSOSTab() {
    final uid = _auth.currentUser?.uid;
    return Column(
      children: [
        const SizedBox(height: 24),
        const Text(
          "Emergency SOS",
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.red),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            "Press the button below to alert your guide immediately.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
        const SizedBox(height: 40),
        GestureDetector(
          onTap: isSendingSOS ? null : _sendSOSAlert,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: isSendingSOS
                  ? const CircularProgressIndicator(
                      color: Colors.white)
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 55),
                        SizedBox(height: 5),
                        Text("SOS",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 40),
        const Text("Recent Alerts",
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('groups')
                .doc(joinedGroupCode)
                .collection('alerts')
                .where('touristUid', isEqualTo: uid)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                    child: Text("No alerts sent yet.",
                        style: TextStyle(color: Colors.grey)));
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data =
                      docs[index].data() as Map<String, dynamic>;
                  final status = data['status'] ?? "active";
                  final Timestamp? ts =
                      data['timestamp'] as Timestamp?;
                  final timeStr = ts != null
                      ? "${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')} - ${ts.toDate().day}/${ts.toDate().month}"
                      : "";

                  Color statusColor = Colors.red;
                  if (status == 'acknowledged')
                    statusColor = Colors.orange;
                  if (status == 'resolved') statusColor = Colors.green;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: const Text("SOS Emergency Triggered",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      subtitle: Text("Time: $timeStr",
                          style: const TextStyle(fontSize: 12)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 2 — CHAT
  // =========================================================================

  Widget _buildChatTab() {
    final uid = _auth.currentUser?.uid;
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('groups')
                .doc(joinedGroupCode)
                .collection('messages')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (context, idx) {
                  final data =
                      docs[idx].data() as Map<String, dynamic>;
                  final senderUid = data['senderUid'];
                  final senderName =
                      data['senderName'] ?? "Unknown";
                  final text = data['text'] ?? "";
                  final Timestamp? ts =
                      data['timestamp'] as Timestamp?;
                  final timeStr = ts != null
                      ? "${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}"
                      : "";

                  final bool isMe = senderUid == uid;

                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF00897B)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft:
                              Radius.circular(isMe ? 12 : 0),
                          bottomRight:
                              Radius.circular(isMe ? 0 : 12),
                        ),
                      ),
                      constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width *
                                  0.75),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(
                              senderName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00897B),
                                  fontSize: 11),
                            ),
                          if (!isMe) const SizedBox(height: 2),
                          Text(
                            text,
                            style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              timeStr,
                              style: TextStyle(
                                  color: isMe
                                      ? Colors.white60
                                      : Colors.grey,
                                  fontSize: 9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: const InputDecoration(
                    hintText: "Type a message...",
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send,
                    color: Color(0xFF00897B)),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}