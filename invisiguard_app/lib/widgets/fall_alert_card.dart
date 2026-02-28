import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/map_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'animated_alert_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FallAlertCard – streams the latest FALL alert from Firestore and shows it.
// If no active fall alert within the last 5 minutes, renders nothing.
// ─────────────────────────────────────────────────────────────────────────────

class FallAlertCard extends StatelessWidget {
  const FallAlertCard({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();

        // The latest alert overall MUST be a fall alert to show the card.
        // If the newest alert is something else (like an SOS), we shouldn't show the fall card.
        final latestAlertData =
            snap.data!.docs.first.data() as Map<String, dynamic>;
        final String latestType = latestAlertData['type'] ?? '';

        if (latestType != 'FALL' && latestType != 'FALL_DETECTED') {
          return const SizedBox();
        }

        // Only show if the alert hasn't been explicitly dismissed
        if (latestAlertData['status'] == 'dismissed') {
          return const SizedBox();
        }

        final data = latestAlertData;
        final String alertId = snap.data!.docs.first.id;

        // Only show if within last 5 minutes
        final ts = data['createdAt'] as Timestamp?;
        if (ts != null) {
          final age = DateTime.now().difference(ts.toDate());
          if (age.inMinutes > 5) return const SizedBox();
        }

        final double confidence =
            (data['confidence'] as num?)?.toDouble() ?? 0.92;
        final String message = data['message'] ?? 'Fall detected';
        final double? lat = (data['latitude'] as num?)?.toDouble();
        final double? lng = (data['longitude'] as num?)?.toDouble();
        final double motionProb =
            (data['ml_motion_probability'] as num?)?.toDouble() ?? 0.0;
        final String motionPred =
            data['ml_motion_prediction'] as String? ?? 'UNKNOWN';

        return _FallCard(
          alertId: alertId,
          confidence: confidence,
          motionProb: motionProb,
          motionPred: motionPred,
          message: message,
          lat: lat,
          lng: lng,
        );
      },
    );
  }
}

class _FallCard extends StatelessWidget {
  final String alertId; // Need this to update the document and hide the card
  final double confidence;
  final double motionProb;
  final String motionPred;
  final String message;
  final double? lat;
  final double? lng;

  const _FallCard({
    required this.alertId,
    required this.confidence,
    required this.motionProb,
    required this.motionPred,
    required this.message,
    required this.lat,
    required this.lng,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).clamp(0, 100).toInt();

    return AnimatedAlertWrapper(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
          ],
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ─────────────────────────────────────────────────────
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                SizedBox(width: 8),
                Text(
                  'Fall Detected',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Confidence bar ─────────────────────────────────────────────
            Text(
              'AI Confidence: $pct%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 8,
                backgroundColor: Colors.grey.shade300,
                color: pct >= 80 ? Colors.red : Colors.orange,
              ),
            ),
            const SizedBox(height: 16),

            // ── Info rows ──────────────────────────────────────────────────
            _infoRow(
              icon: Icons.flash_on,
              label: 'Fall Likelihood',
              value: '${(confidence * 100).toStringAsFixed(1)}%',
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.motion_photos_off,
              label: 'Post-Impact Motion',
              value: '$motionPred (${(motionProb * 100).toStringAsFixed(1)}%)',
              color: motionPred == 'NO-MOTION' ? Colors.red : Colors.orange,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.psychology,
              label: 'AI Verdict',
              value: pct >= 80
                  ? 'High probability of fall'
                  : 'Possible fall – monitoring',
              color: Colors.red,
            ),
            const SizedBox(height: 20),

            // ── Emergency Actions ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.message),
                label: const Text('Send SMS Alert to Emergency Contacts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _sendSMS(context),
              ),
            ),
            const SizedBox(height: 12),

            // ── Secondary actions ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate to Location'),
                onPressed: (lat != null && lng != null)
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MapScreen(initialTarget: LatLng(lat!, lng!)),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(value, style: TextStyle(color: color)),
        ),
      ],
    );
  }

  Future<void> _sendSMS(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    try {
      final contactsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('emergency_contacts')
          .where('receiveAlerts', isEqualTo: true)
          .get();

      final contacts = contactsSnap.docs.map((doc) => doc.data()).toList();
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No emergency contacts enabled')),
        );
        return;
      }

      final String msg =
          '''
⚠️ FALL DETECTED - EMERGENCY!

The device has detected a potential fall. Child may need assistance.
ML Fall Confidence: ${(confidence * 100).toStringAsFixed(1)}%
ML Post-Fall Motion: $motionPred (${(motionProb * 100).toStringAsFixed(1)}%)

📍 Location: https://maps.google.com/?q=${lat ?? 0},${lng ?? 0}
⏰ Time: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}
📱 App: Student Safety System

Please check immediately.
''';

      final encodedMsg = Uri.encodeComponent(msg);
      final phoneNumbers = contacts.map((c) => c['phone'] as String).toList();
      final cleanNumbers = phoneNumbers
          .map((phone) => phone.replaceAll(RegExp(r'[^0-9+]'), ''))
          .toList();
      final numbersString = cleanNumbers.join(',');

      final uri = Uri.parse('sms:$numbersString?body=$encodedMsg');

      bool appOpened = false;

      if (await canLaunchUrl(uri)) {
        appOpened = await launchUrl(uri);
      } else if (cleanNumbers.isNotEmpty) {
        final fallbackUri = Uri.parse(
          'sms:${cleanNumbers.first}?body=$encodedMsg',
        );
        if (await canLaunchUrl(fallbackUri)) {
          appOpened = await launchUrl(fallbackUri);
        }
      }

      // If we successfully opened the SMS app, dismiss the fall card
      if (appOpened) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('alerts')
            .doc(alertId)
            .update({'status': 'dismissed'});
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
