import 'package:flutter/material.dart';
import '../screens/emergency_actions_screen.dart';
import '../screens/map_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'animated_alert_wrapper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GeofenceAlertCard – shown when the child is outside the safe zone.
// Accepts optional lat/lng to navigate directly to child's live location.
// ─────────────────────────────────────────────────────────────────────────────

class GeofenceAlertCard extends StatelessWidget {
  final double? lat;
  final double? lng;

  const GeofenceAlertCard({super.key, this.lat, this.lng});

  @override
  Widget build(BuildContext context) {
    return AnimatedAlertWrapper(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.15),
              blurRadius: 12,
            ),
          ],
          border: Border.all(color: Colors.orange.shade400),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.location_off, color: Colors.orange, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Outside Safe Zone',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Description ────────────────────────────────────────────────
            const Text(
              'Your child has moved outside the geofence boundary. '
              'Their current location is being tracked.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),

            // ── Info rows ──────────────────────────────────────────────────
            _infoRow(
              icon: Icons.shield_outlined,
              label: 'Geofence Status',
              value: 'Breached',
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.gps_fixed,
              label: 'Location Tracking',
              value: 'Active',
              color: Colors.green,
            ),
            const SizedBox(height: 20),

            // ── Actions ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('View on Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          initialTarget: (lat != null && lng != null)
                              ? LatLng(lat!, lng!)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                    ),
                    label: const Text(
                      'Emergency',
                      style: TextStyle(color: Colors.orange),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.orange),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EmergencyActionsScreen(),
                      ),
                    ),
                  ),
                ),
              ],
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
}
