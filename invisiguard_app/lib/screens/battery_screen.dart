import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BatteryScreen extends StatelessWidget {
  const BatteryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Device Battery"),
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('device')
            .doc('battery')
            .snapshots(),
        builder: (context, snapshot) {
          int level = 92;
          bool charging = false;
          String prediction = "Battery healthy";

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            level = data['level'] ?? 92;
            charging = data['charging'] ?? false;
            prediction = data['prediction'] ?? "Battery healthy";
          }

          Color statusColor;
          String statusText;

          if (level <= 20) {
            statusColor = Colors.red;
            statusText = "Critical";
          } else if (level <= 40) {
            statusColor = Colors.orange;
            statusText = "Low";
          } else {
            statusColor = Colors.green;
            statusText = "Good";
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 🔋 MAIN BATTERY CARD
                _card(
                  child: Column(
                    children: [
                      Icon(
                        Icons.battery_full,
                        size: 64,
                        color: statusColor,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "$level%",
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        charging ? "Charging" : "Not Charging",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 📊 STATUS CARD
                _card(
                  child: ListTile(
                    leading:
                        Icon(Icons.info, color: statusColor),
                    title: const Text("Battery Status"),
                    subtitle: Text(statusText),
                  ),
                ),

                const SizedBox(height: 12),

                // 🔮 PREDICTION CARD
                _card(
                  child: ListTile(
                    leading: const Icon(Icons.analytics),
                    title: const Text("Prediction"),
                    subtitle: Text(prediction),
                  ),
                ),

                const SizedBox(height: 24),

                // ℹ️ INFO
                const Text(
                  "Battery data is monitored from the hidden safety device. "
                  "Parents are alerted before the device powers off.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 🧱 CARD
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: child,
    );
  }
}
