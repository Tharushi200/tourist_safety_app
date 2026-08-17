import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'feature_screen.dart';
import 'map_screen.dart';
import 'sos_screen.dart';
import 'nearby_screen.dart';
import 'risk_alert_screen.dart';
import 'profile_screen.dart';

// ===== StatelessWidget → StatefulWidget bawata change una =====
class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {

  // ===== JOIN GROUP DIALOG =====
  void _showJoinGroupDialog(BuildContext context) {
    final TextEditingController codeController = TextEditingController();
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          "Join Tour Group",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Enter the group code from your tour guide:",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                hintText: "000000",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final code = codeController.text.trim();
              final uid = auth.currentUser?.uid;
              final email = auth.currentUser?.email;

              if (code.isEmpty || uid == null) return;

              final groupDoc =
                  await firestore.collection('groups').doc(code).get();

              if (!groupDoc.exists) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Invalid group code!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // ===== Tourist group ekata add karanna =====
              await firestore.collection('groups').doc(code).update({
                'members': FieldValue.arrayUnion([
                  {'uid': uid, 'email': email, 'name': email}
                ]),
              });

              await firestore.collection('users').doc(uid).update({
                'groupCode': code,
              });

              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Joined group $code successfully!"),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text(
              "Join",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),

      appBar: AppBar(
        backgroundColor: Colors.indigo,
        title: const Text(
          "Tourist Safety Dashboard",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,

        actions: [
          // ===== JOIN GROUP BUTTON =====
          IconButton(
            icon: const Icon(Icons.group, color: Colors.white),
            onPressed: () {
              _showJoinGroupDialog(context);
            },
            tooltip: "Join Group",
          ),

          // ===== PROFILE BUTTON =====
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
            tooltip: "Profile",
          ),
        ],
      ),

      body: GridView.count(
        padding: const EdgeInsets.all(20),
        crossAxisCount: 2,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,

        children: [
          dashboardCard(context, "Safe Route", Icons.route, Colors.blue),
          dashboardCard(context, "SOS Emergency", Icons.warning, Colors.red),
          dashboardCard(context, "Nearby Police", Icons.local_police, Colors.indigo),
          dashboardCard(context, "Nearby Hospitals", Icons.local_hospital, Colors.green),
          dashboardCard(context, "Live Location", Icons.location_on, Colors.orange),
          dashboardCard(context, "Risk Alert", Icons.security, Colors.purple),
        ],
      ),
    );
  }

  Widget dashboardCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () {
        if (title == "Safe Route" || title == "Live Location") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MapScreen()),
          );
        } else if (title == "SOS Emergency") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SOSScreen()),
          );
        } else if (title == "Nearby Police") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NearbyScreen(type: "police"),
            ),
          );
        } else if (title == "Nearby Hospitals") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NearbyScreen(type: "hospital"),
            ),
          );
        } else if (title == "Risk Alert") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const RiskAlertScreen(),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FeatureScreen(
                title: title,
                color: color,
                icon: icon,
              ),
            ),
          );
        }
      },

      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 50),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}