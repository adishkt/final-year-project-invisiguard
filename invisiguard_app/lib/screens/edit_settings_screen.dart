import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditSettingsScreen extends StatefulWidget {
  const EditSettingsScreen({super.key});

  @override
  State<EditSettingsScreen> createState() => _EditSettingsScreenState();
}

class _EditSettingsScreenState extends State<EditSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;

  bool _alertsEnabled = true;
  bool _smsEnabled = true;
  double _radius = 300;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (doc.exists) {
      final d = doc.data()!;
      final s = d['settings'];
      if (s != null) {
        _alertsEnabled = s['alertsEnabled'] ?? true;
        _smsEnabled = s['smsEnabled'] ?? true;
        _radius = (s['geofenceRadius'] ?? 300).toDouble();
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'settings': {
        'alertsEnabled': _alertsEnabled,
        'smsEnabled': _smsEnabled,
        'geofenceRadius': _radius.toInt(),
      },
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Settings")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text("Enable Alerts"),
                    value: _alertsEnabled,
                    onChanged: (v) => setState(() => _alertsEnabled = v),
                  ),
                  SwitchListTile(
                    title: const Text("Enable SMS Alerts"),
                    value: _smsEnabled,
                    onChanged: (v) => setState(() => _smsEnabled = v),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    "Geofence Radius: ${_radius.toInt()} meters",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    min: 100,
                    max: 1000,
                    divisions: 18,
                    value: _radius,
                    label: "${_radius.toInt()} m",
                    onChanged: (v) => setState(() => _radius = v),
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text("Save Changes"),
                  ),
                ],
              ),
            ),
    );
  }
}
