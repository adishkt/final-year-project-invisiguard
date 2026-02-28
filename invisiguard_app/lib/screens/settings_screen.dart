import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'edit_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditSettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final settings = data['settings'] ?? {};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section("Alerts"),
              _tile(
                "Alerts Enabled",
                settings['alertsEnabled'] == true ? "Yes" : "No",
              ),
              _tile(
                "SMS Alerts",
                settings['smsEnabled'] == true ? "Yes" : "No",
              ),

              const SizedBox(height: 20),
              _section("Geofence"),
              _tile("Radius", "${settings['geofenceRadius'] ?? 300} meters"),

              const SizedBox(height: 20),
              _section("Appearance"),
              _tile("Theme", settings['theme'] ?? "system"),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _tile(String title, dynamic value) {
    return ListTile(
      title: Text(title),
      subtitle: Text(value?.toString() ?? "-"),
    );
  }
}
