import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

class RiskAlertScreen extends StatefulWidget {
  const RiskAlertScreen({super.key});

  @override
  State<RiskAlertScreen> createState() => _RiskAlertScreenState();
}

class _RiskAlertScreenState extends State<RiskAlertScreen>
    with SingleTickerProviderStateMixin {

  String currentRiskLevel = "CHECKING...";
  Color riskColor = Colors.grey;
  IconData riskIcon = Icons.radar;
  bool isScanning = true;
  int riskScore = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _scanTimer;

  final List<Map<String, dynamic>> riskZones = [
    {
      "zone": "Colombo Fort Area",
      "time": "10:30 PM",
      "risk": "HIGH",
      "color": Colors.red,
      "reason": "High crowd density at night",
    },
    {
      "zone": "Pettah Market",
      "time": "11:00 PM",
      "risk": "MEDIUM",
      "color": Colors.orange,
      "reason": "Pickpocket reports in area",
    },
    {
      "zone": "Galle Face Green",
      "time": "09:00 PM",
      "risk": "LOW",
      "color": Colors.green,
      "reason": "Well lit public area",
    },
    {
      "zone": "Slave Island",
      "time": "10:00 PM",
      "risk": "HIGH",
      "color": Colors.red,
      "reason": "Avoid after dark",
    },
    {
      "zone": "Kollupitiya",
      "time": "08:00 PM",
      "risk": "LOW",
      "color": Colors.green,
      "reason": "Safe tourist zone",
    },
  ];

  final List<Map<String, dynamic>> recentAlerts = [
    {
      "message": "Tourist reported suspicious activity near Pettah",
      "time": "2 mins ago",
      "icon": Icons.warning,
      "color": Colors.orange,
    },
    {
      "message": "Safe zone confirmed: Galle Face area",
      "time": "15 mins ago",
      "icon": Icons.check_circle,
      "color": Colors.green,
    },
    {
      "message": "High risk detected: Colombo Fort at night",
      "time": "1 hour ago",
      "icon": Icons.dangerous,
      "color": Colors.red,
    },
    {
      "message": "Police patrol active: Kollupitiya area",
      "time": "2 hours ago",
      "icon": Icons.local_police,
      "color": Colors.indigo,
    },
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scanTimer = Timer(const Duration(seconds: 3), () {
      _analyzeRisk();
    });
  }

  void _analyzeRisk() {
    final random = Random();
    final score = random.nextInt(100);

    setState(() {
      isScanning = false;
      riskScore = score;

      if (score >= 70) {
        currentRiskLevel = "HIGH RISK";
        riskColor = Colors.red;
        riskIcon = Icons.dangerous;
      } else if (score >= 40) {
        currentRiskLevel = "MEDIUM RISK";
        riskColor = Colors.orange;
        riskIcon = Icons.warning;
      } else {
        currentRiskLevel = "SAFE ZONE";
        riskColor = Colors.green;
        riskIcon = Icons.verified_user;
      }
    });

    if (score >= 70) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _showHighRiskDialog();
      });
    }
  }

  void _showHighRiskDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.dangerous, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text(
              "HIGH RISK DETECTED",
              style: TextStyle(
                color: Colors.red,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "⚠️ You are entering a high risk area!",
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 10),
            Text(
              "AI has detected potential danger based on:",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            SizedBox(height: 8),
            Text("• Crime reports in this area"),
            Text("• High risk time of day"),
            Text("• Tourist incident history"),
            SizedBox(height: 15),
            Text(
              "Please choose a safer route.",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Dismiss"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Get Safe Route",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _rescan() {
    setState(() {
      isScanning = true;
      currentRiskLevel = "CHECKING...";
      riskColor = Colors.grey;
      riskIcon = Icons.radar;
      riskScore = 0;
    });

    _scanTimer = Timer(const Duration(seconds: 3), () {
      _analyzeRisk();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text(
          "AI Risk Alert System",
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _rescan,
            tooltip: "Rescan",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRiskStatusCard(),
            const SizedBox(height: 20),
            if (!isScanning) _buildRiskFactors(),
            const SizedBox(height: 20),
            const Text(
              "Risk Zones Near You",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildRiskZonesList(),
            const SizedBox(height: 20),
            const Text(
              "Recent Alerts",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildRecentAlerts(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ===== FIX: withOpacity → withValues =====
  Widget _buildRiskStatusCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isScanning ? _pulseAnimation.value : 1.0,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: riskColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: riskColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  isScanning ? Icons.radar : riskIcon,
                  color: Colors.white,
                  size: 70,
                ),
                const SizedBox(height: 15),
                Text(
                  isScanning ? "AI SCANNING..." : currentRiskLevel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isScanning
                      ? "Analyzing location safety data..."
                      : "Risk Score: $riskScore / 100",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                if (!isScanning) ...[
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: riskScore / 100,
                      backgroundColor: Colors.white30,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRiskFactors() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "AI Analysis Factors",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _buildFactor("Crime Reports",
              riskScore > 60 ? "High" : "Low",
              riskScore > 60 ? Colors.red : Colors.green),
          _buildFactor("Time of Day", "Night", Colors.orange),
          _buildFactor("Tourist Incidents",
              riskScore > 40 ? "Reported" : "None",
              riskScore > 40 ? Colors.orange : Colors.green),
          _buildFactor("Police Presence",
              riskScore < 50 ? "Active" : "Limited",
              riskScore < 50 ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Widget _buildFactor(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskZonesList() {
    return Column(
      children: riskZones.map((zone) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: zone["color"],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone["zone"],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      zone["reason"],
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (zone["color"] as Color)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      zone["risk"],
                      style: TextStyle(
                        color: zone["color"],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    zone["time"],
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentAlerts() {
    return Column(
      children: recentAlerts.map((alert) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (alert["color"] as Color).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  alert["icon"],
                  color: alert["color"],
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert["message"],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alert["time"],
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}