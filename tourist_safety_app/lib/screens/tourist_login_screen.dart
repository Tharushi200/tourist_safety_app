import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import 'tourist_dashboard.dart';

class TouristLoginScreen extends StatefulWidget {
  const TouristLoginScreen({super.key});

  @override
  State<TouristLoginScreen> createState() => _TouristLoginScreenState();
}

class _TouristLoginScreenState extends State<TouristLoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _codeController = TextEditingController();
  bool _isJoining = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: const Text('Tourist Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the group code provided by your guide to start tracking.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.teal),
              decoration: InputDecoration(
                hintText: '161EF41E',
                hintStyle: TextStyle(color: Colors.grey.shade300, letterSpacing: 4),
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isJoining ? null : _joinGroup,
              icon: const Icon(Icons.group_add, color: Colors.white),
              label: _isJoining
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Join Group', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinGroup() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a group code')));
      return;
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not logged in')));
      return;
    }
    setState(() => _isJoining = true);
    try {
      // Verify the group exists
      final groupDoc = await _firestore.collection('groups').doc(code).get();
      if (!groupDoc.exists) {
        throw Exception('Invalid group code');
      }
      // Add tourist to the group's members sub‑collection
      await _firestore
          .collection('groups')
          .doc(code)
          .collection('members')
          .doc(uid)
          .set({
        'name': _auth.currentUser?.email ?? 'Tourist',
        'email': _auth.currentUser?.email ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      // Record the group code on the user's document
      await _firestore.collection('users').doc(uid).update({'groupCode': code});

      // Start location sharing (mirrors TouristDashboard logic)
      await _startLocationSharing(code);

      // Navigate to the main tourist dashboard
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TouristDashboard()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // Minimal location‑sharing implementation (same as TouristDashboard)
  Future<void> _startLocationSharing(String code) async {
    var permission = await Permission.location.request();
    if (permission.isDenied) return;
    await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    const LocationSettings settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      await _firestore
          .collection('groups')
          .doc(code)
          .collection('locations')
          .doc(uid)
          .set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
        'name': _auth.currentUser?.email ?? 'Tourist',
        'role': 'tourist',
      });
    });
  }
}
