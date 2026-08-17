import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:async';
import 'login_screen.dart';

class GuideDashboard extends StatefulWidget {
  const GuideDashboard({super.key});

  @override
  State<GuideDashboard> createState() => _GuideDashboardState();
}

class _GuideDashboardState extends State<GuideDashboard> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String activeGroupCode = "";
  String activeGroupName = "";
  String guideName = "";
  bool isLoading = true;
  bool isCreatingGroup = false;
  List<dynamic> touristLocs = [];

  int _currentIndex = 0; // Tab index: 0: Map, 1: Alerts, 2: Members, 3: Chat

  // Controllers
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();

  // Location Stream Subscription
  StreamSubscription<Position>? _locationSubscription;

  LatLng _currentGuidePosition = const LatLng(7.8731, 80.7718);
  GoogleMapController? _mapController;
  MapType _currentMapType = MapType.normal;

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
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 15));
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

  @override
  void initState() {
    super.initState();
    _loadGuideData();
  }

  @override
  void dispose() {
    _stopLocationSharing();
    _groupNameController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  // ===== LOAD INITIAL DATA =====
  Future<void> _loadGuideData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          guideName = data['name'] ?? "";
          activeGroupCode = data['groupCode'] ?? "";
          isLoading = false;
        });

        if (activeGroupCode.isNotEmpty) {
          // Fetch active group name
          final groupDoc = await _firestore.collection('groups').doc(activeGroupCode).get();
          if (groupDoc.exists) {
            final gData = groupDoc.data() as Map<String, dynamic>;
            setState(() {
              activeGroupName = gData['name'] ?? "Active Group";
            });
          }
          _startLocationSharing(activeGroupCode);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // ===== GENERATE RANDOM 8-CHAR ALPHANUMERIC UPPERCASE CODE =====
  String _generate8CharGroupCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(8, (i) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueCode() async {
    while (true) {
      final code = _generate8CharGroupCode();
      final doc = await _firestore.collection('groups').doc(code).get();
      if (!doc.exists) {
        return code;
      }
    }
  }

  // ===== CREATE GROUP =====
  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a tour group name"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => isCreatingGroup = true);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final code = await _generateUniqueCode();

      // Create group document
      await _firestore.collection('groups').doc(code).set({
        'name': groupName,
        'guideUid': uid,
        'guideName': guideName.isNotEmpty ? guideName : (_auth.currentUser?.email ?? "Guide"),
        'guideEmail': _auth.currentUser?.email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update user doc with current groupCode
      await _firestore.collection('users').doc(uid).update({
        'groupCode': code,
      });

      _groupNameController.clear();

      if (!mounted) return;
      setState(() {
        activeGroupCode = code;
        activeGroupName = groupName;
        isCreatingGroup = false;
        _currentIndex = 0; // Default to map tab
      });

      // Start location sharing for this active group
      _startLocationSharing(code);

      // Show Success Dialog
      _showGroupCreatedDialog(code);
    } catch (e) {
      setState(() => isCreatingGroup = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to create group: ${e.toString()}")),
      );
    }
  }

  // ===== GROUP CREATED DIALOG (MATCHES SCREENSHOT EXACTLY) =====
  void _showGroupCreatedDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFF3F4F6),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Text(
                "Group Created!",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D2129),
                ),
              ),
              const SizedBox(height: 16),

              // Subtitle
              Center(
                child: Text(
                  "Share this code with your tourists:",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Code Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F2FE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBCE0FD), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Code copied!"),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFF1565C0),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Start Guiding Button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Start Guiding",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ===== SWITCH / DEACTIVATE ACTIVE GROUP =====
  Future<void> _switchGroup(String newCode, String newName) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _stopLocationSharing();

    await _firestore.collection('users').doc(uid).update({
      'groupCode': newCode,
    });

    setState(() {
      activeGroupCode = newCode;
      activeGroupName = newName;
      _currentIndex = 0;
    });

    if (newCode.isNotEmpty) {
      _startLocationSharing(newCode);
    }
  }

  Future<void> _leaveActiveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Leave Active Group?"),
        content: const Text("You will stop location sharing and viewing live tourist updates for this group."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Leave", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _switchGroup("", "");
    }
  }

  // ===== LIVE LOCATION SHARING =====
  Future<void> _startLocationSharing(String code) async {
    _stopLocationSharing();

    var permission = await Permission.location.request();
    if (permission.isDenied) {
      _showPermissionRetryDialog(code);
      return;
    }

    try {
      Position initPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _currentGuidePosition = LatLng(initPos.latitude, initPos.longitude);
      });
    } catch (_) {}

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _locationSubscription = Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      int battery = 95 - (DateTime.now().minute % 15);

      setState(() {
        _currentGuidePosition = LatLng(pos.latitude, pos.longitude);
      });

      await _firestore
          .collection('groups')
          .doc(code)
          .collection('locations')
          .doc(uid)
          .set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
        'batteryPercent': battery,
        'name': guideName.isNotEmpty ? guideName : (_auth.currentUser?.email ?? "Guide"),
        'role': 'guide',
      });
    });
  }

  void _stopLocationSharing() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  void _showPermissionRetryDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Location Permission Required"),
        content: const Text("Location permission is needed to share updates and view the group map. Please grant it."),
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

  // ===== LOGOUT =====
  Future<void> _logout() async {
    _stopLocationSharing();
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // ===== SEND CHAT MESSAGE =====
  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('groups')
        .doc(activeGroupCode)
        .collection('messages')
        .add({
      'senderUid': uid,
      'senderName': guideName.isNotEmpty ? guideName : (_auth.currentUser?.email ?? "Guide"),
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _chatController.clear();
  }

  // ===== PROFILE DIALOG =====
  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Color(0xFF1565C0), size: 30),
            SizedBox(width: 10),
            Text("Guide Profile", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${guideName.isNotEmpty ? guideName : 'Guide'}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text("Email: ${_auth.currentUser?.email ?? 'N/A'}", style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text("Role: Tour Guide", style: TextStyle(fontSize: 14, color: Colors.grey)),
            if (activeGroupCode.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tour, color: Color(0xFF1565C0), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text("Active: $activeGroupName ($activeGroupCode)",
                          style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
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

  // ===== HISTORY BOTTOM SHEET =====
  void _showGroupHistorySheet() {
    final uid = _auth.currentUser?.uid;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history, color: Color(0xFF1565C0)),
                      SizedBox(width: 8),
                      Text("Your Tour Groups", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('groups')
                      .where('guideUid', isEqualTo: uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text("No groups created yet.", style: TextStyle(color: Colors.grey)),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final code = docs[index].id;
                        final name = data['name'] ?? "Unnamed Group";
                        final bool isActive = code == activeGroupCode;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isActive ? const Color(0xFF1565C0) : Colors.grey.shade200,
                              child: Icon(Icons.tour, color: isActive ? Colors.white : Colors.grey),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("Code: $code", style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
                            trailing: isActive
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text("Active", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1565C0),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _switchGroup(code, name);
                                    },
                                    child: const Text("Switch", style: TextStyle(color: Colors.white)),
                                  ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================= MAIN BUILD METHOD =================
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
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        title: const Text(
          "SmartTour - Guide",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: "Tour Groups History",
            onPressed: _showGroupHistorySheet,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            tooltip: "Profile",
            onPressed: _showProfileDialog,
          ),
        ],
      ),
      body: activeGroupCode.isEmpty
          ? _buildNoActiveGroupTab(_currentIndex)
          : _buildActiveGroupTab(_currentIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
        elevation: 8,
        indicatorColor: const Color(0xFFE3F2FD),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: Color(0xFF1565C0)),
            label: "Map",
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_outlined),
            selectedIcon: Icon(Icons.notifications, color: Color(0xFF1565C0)),
            label: "Alerts",
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: Color(0xFF1565C0)),
            label: "Members",
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat, color: Color(0xFF1565C0)),
            label: "Chat",
          ),
        ],
      ),
    );
  }

  // ================= TABS WHEN NO GROUP IS ACTIVE =================
  Widget _buildNoActiveGroupTab(int index) {
    if (index == 0) {
      return _buildGroupSelectionScreen();
    }

    String tabTitle = "Tab";
    IconData tabIcon = Icons.info;
    if (index == 1) {
      tabTitle = "Alerts";
      tabIcon = Icons.notifications_none_outlined;
    } else if (index == 2) {
      tabTitle = "Members";
      tabIcon = Icons.people_outline;
    } else if (index == 3) {
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
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(tabIcon, size: 48, color: const Color(0xFF1565C0)),
            ),
            const SizedBox(height: 20),
            Text(
              "No Active Tour Group",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            Text(
              "Create a tour group on the Map tab to access $tabTitle.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => setState(() => _currentIndex = 0),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Create Tour Group", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ================= SCREEN: GROUP CREATION (MATCHES SCREENSHOT EXACTLY) =================
  Widget _buildGroupSelectionScreen() {
    final displayName = guideName.isNotEmpty ? guideName : "Ramesha Dasangi";

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Welcome Greeting
          Text(
            "Welcome, $displayName!",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1D2129),
            ),
          ),
          const SizedBox(height: 24),

          // 2. Featured Blue Banner Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flag_outlined,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Create your tour group",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Tourists will use the group code to join",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 3. Form Section Label
          Text(
            "Tour group name",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 10),

          // 4. Tour Group Name TextField
          TextField(
            controller: _groupNameController,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              fillColor: Colors.white,
              filled: true,
              prefixIcon: const Icon(
                Icons.flag_outlined,
                color: Colors.grey,
                size: 26,
              ),
              hintText: "e.g. Colombo Heritage Walk – Grou...",
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
                borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 5. Create Group & Get Code Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: isCreatingGroup ? null : _createGroup,
              child: isCreatingGroup
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      "Create Group & Get Code",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB ROUTING FOR ACTIVE GROUP =================
  Widget _buildActiveGroupTab(int index) {
    switch (index) {
      case 0:
        return _buildMapTab();
      case 1:
        return _buildAlertsTab();
      case 2:
        return _buildMembersTab();
      case 3:
        return _buildChatTab();
      default:
        return const Center(child: Text("Tab not found"));
    }
  }

  // ================= TAB 1: MAP VIEW =================
  Widget _buildMapTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .doc(activeGroupCode)
          .collection('locations')
          .snapshots(),
      builder: (context, snapshot) {
        final Set<Marker> markers = {};

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
            final hue = isGuide
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueGreen;

            markers.add(Marker(
              markerId: MarkerId(uid),
              position: position,
              icon: BitmapDescriptor.defaultMarkerWithHue(hue),
              infoWindow: InfoWindow(
                title: isGuide ? '🧭 Guide: $name' : '🧑‍🤝‍🧑 $name',
                snippet: isGuide ? 'Tour Leader' : 'Tourist Member',
              ),
            ));
          }

          // Auto-fit camera if markers updated
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fitGroupBounds(markers);
          });
        }

        return Stack(
          children: [
            // ── Google Map ──────────────────────────────────────────────
            GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                if (markers.isNotEmpty) _fitGroupBounds(markers);
              },
              initialCameraPosition: CameraPosition(target: _currentGuidePosition, zoom: 15),
              mapType: _currentMapType,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: markers,
            ),

            // ── Top info card ───────────────────────────────────────────
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tour, color: Color(0xFF1565C0), size: 22),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeGroupName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              'Code: $activeGroupCode',
                              style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Members count badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.people, color: Color(0xFF1565C0), size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${markers.isEmpty ? 0 : markers.length}',
                                style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Color(0xFF1565C0), size: 20),
                          tooltip: 'Copy Code',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: activeGroupCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Code $activeGroupCode copied!')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
                          tooltip: 'End Tour',
                          onPressed: _leaveActiveGroup,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Legend ──────────────────────────────────────────────────
            Positioned(
              bottom: 100,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendItem(Colors.blue[700]!, '🧭 Guide'),
                    const SizedBox(height: 4),
                    _legendItem(Colors.green[600]!, '🧑‍🤝‍🧑 Tourist'),
                  ],
                ),
              ),
            ),

            // ── FABs (right side) ────────────────────────────────────────
            Positioned(
              bottom: 100,
              right: 12,
              child: Column(
                children: [
                  // Re-center on my location
                  FloatingActionButton.small(
                    heroTag: 'guide_recenter',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_currentGuidePosition, 16),
                      );
                    },
                    child: const Icon(Icons.my_location, color: Color(0xFF1565C0)),
                  ),
                  const SizedBox(height: 8),
                  // Fit all markers
                  FloatingActionButton.small(
                    heroTag: 'guide_fit_all',
                    backgroundColor: Colors.white,
                    onPressed: () => _fitGroupBounds(markers),
                    child: const Icon(Icons.fit_screen, color: Color(0xFF1565C0)),
                  ),
                  const SizedBox(height: 8),
                  // Toggle map type
                  FloatingActionButton.small(
                    heroTag: 'guide_map_type',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _currentMapType = _currentMapType == MapType.normal
                            ? MapType.satellite
                            : MapType.normal;
                      });
                    },
                    child: Icon(
                      _currentMapType == MapType.normal
                          ? Icons.satellite_alt
                          : Icons.map,
                      color: const Color(0xFF1565C0),
                    ),
                  ),
                ],
              ),
            ),

            // ── Loading overlay ─────────────────────────────────────────
            if (snapshot.connectionState == ConnectionState.waiting && markers.isEmpty)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF1565C0)),
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ================= TAB 2: ALERTS VIEW =================
  Widget _buildAlertsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .doc(activeGroupCode)
          .collection('alerts')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final activeAlerts = docs.where((doc) => doc['status'] == 'active' || doc['status'] == 'acknowledged').toList();
        final resolvedAlerts = docs.where((doc) => doc['status'] == 'resolved').toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Active Emergencies", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Text("${activeAlerts.length}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (activeAlerts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text("No active alerts. Everyone is safe! 👍", style: TextStyle(color: Colors.grey))),
                ),
              )
            else
              ...activeAlerts.map((doc) => _buildAlertCard(doc)),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Resolved History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                  child: Text("${resolvedAlerts.length}", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (resolvedAlerts.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(10), child: Text("No alerts resolved yet.", style: TextStyle(color: Colors.grey))))
            else
              ...resolvedAlerts.map((doc) => _buildAlertCard(doc)),
          ],
        );
      },
    );
  }

  Widget _buildAlertCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['touristName'] ?? "Unknown Tourist";
    final status = data['status'] ?? "active";
    final Timestamp? ts = data['timestamp'] as Timestamp?;
    final timeStr = ts != null 
        ? "${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')} - ${ts.toDate().day}/${ts.toDate().month}"
        : "";

    Color statusColor = Colors.red;
    if (status == 'acknowledged') statusColor = Colors.orange;
    if (status == 'resolved') statusColor = Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              "triggered an SOS emergency!",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text("Time: $timeStr", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (status != 'resolved') ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'active')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, elevation: 0),
                      onPressed: () async {
                        await _firestore
                            .collection('groups')
                            .doc(activeGroupCode)
                            .collection('alerts')
                            .doc(doc.id)
                            .update({'status': 'acknowledged'});
                      },
                      icon: const Icon(Icons.visibility, color: Colors.white, size: 16),
                      label: const Text("Acknowledge", style: TextStyle(color: Colors.white)),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, elevation: 0),
                    onPressed: () async {
                      await _firestore
                          .collection('groups')
                          .doc(activeGroupCode)
                          .collection('alerts')
                          .doc(doc.id)
                          .update({'status': 'resolved'});
                    },
                    icon: const Icon(Icons.check, color: Colors.white, size: 16),
                    label: const Text("Resolve", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  // ================= TAB 3: MEMBERS VIEW =================
  Widget _buildMembersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .doc(activeGroupCode)
          .collection('members')
          .snapshots(),
      builder: (context, membersSnapshot) {
        if (membersSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final membersDocs = membersSnapshot.data?.docs ?? [];

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('groups')
              .doc(activeGroupCode)
              .collection('locations')
              .snapshots(),
          builder: (context, locationsSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('groups')
                  .doc(activeGroupCode)
                  .collection('alerts')
                  .snapshots(),
              builder: (context, alertsSnapshot) {
                final locsMap = <String, Map<String, dynamic>>{};
                if (locationsSnapshot.hasData) {
                  for (var doc in locationsSnapshot.data!.docs) {
                    locsMap[doc.id] = doc.data() as Map<String, dynamic>;
                  }
                }

                int totalJoined = membersDocs.length;
                int liveGpsCount = 0;
                int activeSosCount = 0;

                if (alertsSnapshot.hasData) {
                  activeSosCount = alertsSnapshot.data!.docs
                      .where((d) => d['status'] == 'active' || d['status'] == 'acknowledged')
                      .length;
                }

                final now = DateTime.now();
                locsMap.forEach((uid, data) {
                  final ts = data['updatedAt'] as Timestamp?;
                  if (ts != null) {
                    final diff = now.difference(ts.toDate()).inSeconds;
                    if (diff < 90) {
                      liveGpsCount++;
                    }
                  }
                });

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: Colors.blue.shade50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem("Joined", "$totalJoined", Colors.black),
                          _buildStatItem("Live GPS", "$liveGpsCount", Colors.green),
                          _buildStatItem("Active SOS", "$activeSosCount", Colors.red),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: membersDocs.isEmpty
                          ? const Center(child: Text("No members in this group yet.", style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: membersDocs.length,
                              itemBuilder: (context, idx) {
                                final member = membersDocs[idx].data() as Map<String, dynamic>;
                                final String uid = membersDocs[idx].id;
                                final name = member['name'] ?? "Tourist";

                                final locData = locsMap[uid];
                                final battery = locData?['batteryPercent'] ?? 100;
                                final Timestamp? ts = locData?['updatedAt'] as Timestamp?;

                                bool isLive = false;
                                if (ts != null) {
                                  isLive = now.difference(ts.toDate()).inSeconds < 90;
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isLive ? Colors.green.shade50 : Colors.grey.shade100,
                                      child: Icon(Icons.person, color: isLive ? Colors.green : Colors.grey),
                                    ),
                                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Row(
                                      children: [
                                        Icon(Icons.circle, size: 8, color: isLive ? Colors.green : Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(isLive ? "Live GPS" : "Offline", style: TextStyle(color: isLive ? Colors.green : Colors.grey, fontSize: 12)),
                                        const SizedBox(width: 15),
                                        const Icon(Icons.battery_std, size: 14, color: Colors.grey),
                                        Text(" $battery%", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  // ================= TAB 4: GROUP CHAT =================
  Widget _buildChatTab() {
    final uid = _auth.currentUser?.uid;
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('groups')
                .doc(activeGroupCode)
                .collection('messages')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (context, idx) {
                  final data = docs[idx].data() as Map<String, dynamic>;
                  final senderUid = data['senderUid'];
                  final senderName = data['senderName'] ?? "Unknown";
                  final text = data['text'] ?? "";
                  final Timestamp? ts = data['timestamp'] as Timestamp?;
                  final timeStr = ts != null 
                      ? "${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}"
                      : "";

                  final bool isMe = senderUid == uid;

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF1565C0) : Colors.grey.shade200,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isMe ? 12 : 0),
                          bottomRight: Radius.circular(isMe ? 0 : 12),
                        ),
                      ),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Text(
                              senderName,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1565C0), fontSize: 11),
                            ),
                          if (!isMe) const SizedBox(height: 2),
                          Text(
                            text,
                            style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              timeStr,
                              style: TextStyle(color: isMe ? Colors.white60 : Colors.grey, fontSize: 9),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
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
                icon: const Icon(Icons.send, color: Color(0xFF1565C0)),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}