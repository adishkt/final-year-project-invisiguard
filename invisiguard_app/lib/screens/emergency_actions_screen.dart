import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyActionsScreen extends StatelessWidget {
  const EmergencyActionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Actions")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('emergency_contacts')
            .where('receiveAlerts', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No contacts enabled for alerts"),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _infoCard(),

              const SizedBox(height: 12),

              ...snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(data['name']),
                    subtitle:
                        Text("${data['relation']} • ${data['phone']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.sms, color: Colors.blue),
                          onPressed: () =>
                              _mockSendSMS(context, data),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: () =>
                              _mockCall(context, data),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }

  // ℹ️ TOP INFO
  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        "⚠️ Emergency mode active.\nSend alert messages or call selected contacts immediately.",
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  // 📩 MOCK SMS
  void _mockSendSMS(BuildContext context, Map<String, dynamic> contact) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "📩 SMS sent to ${contact['name']} (${contact['phone']})",
        ),
      ),
    );
  }

  // 📞 MOCK CALL
  void _mockCall(BuildContext context, Map<String, dynamic> contact) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "📞 Calling ${contact['name']} (${contact['phone']})",
        ),
      ),
    );
  }
}
