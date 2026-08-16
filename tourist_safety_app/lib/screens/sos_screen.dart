import 'package:flutter/material.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  bool alertSent = false;
  int tapCount = 0;

  void handleSOSTap() {
    setState(() {
      tapCount++;
    });

    if (tapCount >= 3) {
      setState(() {
        alertSent = true;
        tapCount = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚨 SOS Alert Sent! Police notified with your location."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Press ${3 - tapCount} more time(s) to send SOS"),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red,
        title: const Text("SOS Emergency", style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Press 3 times to send\nsilent SOS alert",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: handleSOSTap,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: alertSent ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (alertSent ? Colors.green : Colors.red)
                          .withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      alertSent ? Icons.check : Icons.warning,
                      color: Colors.white,
                      size: 80,
                    ),
                    Text(
                      alertSent ? "SENT!" : "SOS",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            if (alertSent)
              const Text(
                "✅ Police and emergency contacts\nhave been notified",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}