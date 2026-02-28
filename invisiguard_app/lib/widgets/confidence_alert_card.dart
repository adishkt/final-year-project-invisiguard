import 'package:flutter/material.dart';
import '../screens/emergency_actions_screen.dart';

class ConfidenceAlertCard extends StatelessWidget {
  const ConfidenceAlertCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.red.withOpacity(0.15), blurRadius: 12),
        ],
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🚨 Title
          const Text(
            "🚨 Fall Detected",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),

          const SizedBox(height: 12),

          // 📊 Confidence Meter
          const Text(
            "AI Confidence: 92%",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: 0.92,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            color: Colors.red,
          ),

          const SizedBox(height: 16),

          // 🔍 Indicators
          _infoRow(
            icon: Icons.flash_on,
            label: "Impact Force",
            value: "High",
            color: Colors.red,
          ),
          const SizedBox(height: 8),

          _infoRow(
            icon: Icons.motion_photos_off,
            label: "Post-Impact Movement",
            value: "No movement (30s)",
            color: Colors.red,
          ),
          const SizedBox(height: 8),

          _infoRow(
            icon: Icons.psychology,
            label: "AI Verdict",
            value: "High probability of fall",
            color: Colors.red,
          ),

          const SizedBox(height: 20),

          // 🚨 Emergency Actions
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.warning),
              label: const Text("Emergency Actions"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EmergencyActionsScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ℹ️ Secondary actions (disabled / mock)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: null, // future: mic access
                  icon: const Icon(Icons.hearing),
                  label: const Text("Listen In"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: null, // future: maps navigation
                  icon: const Icon(Icons.navigation),
                  label: const Text("Navigate"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text("$label: ", style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(value, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
