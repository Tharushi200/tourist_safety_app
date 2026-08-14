import 'package:flutter/material.dart';

class FeatureScreen extends StatelessWidget {

  final String title;
  final Color color;
  final IconData icon;

  const FeatureScreen({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        backgroundColor: color,

        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            Icon(
              icon,
              size: 120,
              color: color,
            ),

            const SizedBox(height: 20),

            Text(
              title,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "This feature screen is under development.",
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}