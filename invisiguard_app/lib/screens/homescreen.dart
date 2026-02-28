import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'login_screen.dart';
import 'map_screen.dart';
import 'alert_history_screen.dart';
import 'location_history_screen.dart';
import 'emergency_contacts_screen.dart';
import 'battery_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';

import '../widgets/fall_alert_card.dart';
import '../widgets/geofence_alert_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _sosLoading = false;
  bool _fallAlertLoading = false;
  StreamSubscription<DatabaseEvent>? _deviceSosSub;
  StreamSubscription<DatabaseEvent>? _deviceAlertSub;

  Timer? _historyTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
      lowerBound: 0.85,
      upperBound: 1.1,
    )..repeat(reverse: true);

    _listenToDeviceSos();
    _listenToDeviceAlerts();
    _historyTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _saveLocationHistory(),
    );
  }

  void _listenToDeviceAlerts() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _deviceAlertSub = FirebaseDatabase.instance
        .ref('student')
        .onValue
        .listen(
          (event) async {
            final val = event.snapshot.value;
            if (val != null && val is Map) {
              final Map<String, dynamic> data = Map<String, dynamic>.from(val);
              if (data['is_alert'] == true &&
                  data['alert_reason'] == 'fall_detected') {
                debugPrint('[HomeScreen] Device Fall Alert triggered!');
                if (mounted) {
                  final fallProb =
                      (data['ml_fall_probability'] as num?)?.toDouble() ?? 0.95;
                  final motionProb =
                      (data['ml_motion_probability'] as num?)?.toDouble() ??
                      0.0;
                  final motionPred =
                      data['ml_motion_prediction'] as String? ?? 'UNKNOWN';

                  // Reset is_alert to false so it can trigger again later
                  await FirebaseDatabase.instance.ref('student').update({
                    'is_alert': false,
                  });
                  await _triggerFallAlert(
                    context,
                    uid,
                    fallProb,
                    motionProb,
                    motionPred,
                  );
                }
              }
            }
          },
          onError: (error) {
            debugPrint('[HomeScreen] Error listening to device alerts: $error');
          },
        );
  }

  void _listenToDeviceSos() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _deviceSosSub = FirebaseDatabase.instance
        .ref('student/sos')
        .onValue
        .listen(
          (event) async {
            final val = event.snapshot.value;
            if (val == 1 || val == '1') {
              debugPrint('[HomeScreen] Device SOS triggered!');

              if (mounted) {
                // Reset the value to 0 so it can be triggered again
                await FirebaseDatabase.instance.ref('student/sos').set(0);
                await _triggerSOS(context, uid);
              }
            }
          },
          onError: (error) {
            debugPrint('[HomeScreen] Error listening to device SOS: $error');
          },
        );
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _deviceSosSub?.cancel();
    _deviceAlertSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _saveLocationHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('student').get();
      if (snap.value != null && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        double? lat = _toDouble(data['latitude'] ?? data['lat']);
        double? lng = _toDouble(data['longitude'] ?? data['lng']);
        if (lat != null && lng != null && lat != 0 && lng != 0) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('location_history')
              .add({
                'latitude': lat,
                'longitude': lng,
                'timestamp': Timestamp.now(),
              });
          debugPrint('[HomeScreen] Saved location history: $lat, $lng');
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error saving location history: $e');
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // 🧠 DEVICE ONLINE CHECK LOGIC
  bool _isDeviceOnline(Timestamp? lastSeen) {
    if (lastSeen == null) return false;
    final now = DateTime.now();
    final last = lastSeen.toDate();
    return now.difference(last).inSeconds <= 60;
  }

  // 🚨 FALL ALERT FUNCTION - SENDS TO ALL EMERGENCY CONTACTS
  Future<void> _triggerFallAlert(
    BuildContext context,
    String uid,
    double mlFallProb,
    double mlMotionProb,
    String mlMotionPred,
  ) async {
    if (_fallAlertLoading) return;

    setState(() => _fallAlertLoading = true);

    try {
      // 1️⃣ CHECK DEVICE ONLINE STATUS
      final deviceStatusDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('device')
          .doc('status')
          .get();

      bool deviceOnline = true;
      if (deviceStatusDoc.exists) {
        final data = deviceStatusDoc.data()!;
        deviceOnline = _isDeviceOnline(data['lastSeen']);
      }

      if (!deviceOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Device offline - SMS only mode"),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // 2️⃣ GET CURRENT LOCATION
      final locationDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('location')
          .doc('current')
          .get();

      LatLng location;
      if (!locationDoc.exists || locationDoc.data() == null) {
        location = const LatLng(10.039298, 76.325);
      } else {
        final loc = locationDoc.data()!;
        location = LatLng(
          loc['latitude'] ?? 10.039298,
          loc['longitude'] ?? 76.325,
        );
      }

      // 3️⃣ GET ALL EMERGENCY CONTACTS
      final contactsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('emergency_contacts')
          .where('receiveAlerts', isEqualTo: true)
          .get();

      final contacts = contactsSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Emergency Contact',
          'phone': data['phone'] as String,
          'id': doc.id,
        };
      }).toList();

      final contactCount = contacts.length;

      if (contactCount == 0) {
        throw Exception("No emergency contacts enabled. Add contacts first.");
      }

      // 4️⃣ CREATE FALL ALERT IN FIRESTORE
      final alertRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .doc();

      final alertId = alertRef.id;

      final alertData = {
        'id': alertId,
        'type': 'FALL_DETECTED',
        'status': 'sent',
        'message': '⚠️ Automatic Fall Alert triggered by device',
        'confidence': mlFallProb, // Passed from device ML
        'ml_motion_probability': mlMotionProb,
        'ml_motion_prediction': mlMotionPred,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'googleMapsLink':
            'https://maps.google.com/?q=${location.latitude},${location.longitude}',
        // We no longer automatically send SMS from here, the user sends it via the UI
        'smsSent': false,
        'timestamp': DateTime.now().toIso8601String(),
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };

      await alertRef.set(alertData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "⚠️ Fall Alert generated. Tap 'Send SMS Alert' on the screen.",
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() => _fallAlertLoading = false);
    } catch (e) {
      setState(() => _fallAlertLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Fall Alert Failed: ${e.toString().replaceAll('Exception:', '').trim()}",
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 🚨 SOS FUNCTION - SENDS TO ALL EMERGENCY CONTACTS
  Future<void> _triggerSOS(BuildContext context, String uid) async {
    if (_sosLoading) return;

    setState(() => _sosLoading = true);

    try {
      // 1️⃣ CHECK DEVICE ONLINE STATUS
      final deviceStatusDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('device')
          .doc('status')
          .get();

      bool deviceOnline = true;
      if (deviceStatusDoc.exists) {
        final data = deviceStatusDoc.data()!;
        deviceOnline = _isDeviceOnline(data['lastSeen']);
      }

      if (!deviceOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Device offline - SMS only mode"),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // 2️⃣ GET CURRENT LOCATION
      final locationDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('location')
          .doc('current')
          .get();

      LatLng location;
      if (!locationDoc.exists || locationDoc.data() == null) {
        // Fallback location if GPS is not available yet
        location = const LatLng(10.039298, 76.325);
      } else {
        final loc = locationDoc.data()!;
        location = LatLng(
          loc['latitude'] ?? 10.039298,
          loc['longitude'] ?? 76.325,
        );
      }

      // 3️⃣ GET ALL EMERGENCY CONTACTS
      final contactsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('emergency_contacts')
          .where('receiveAlerts', isEqualTo: true)
          .get();

      final contacts = contactsSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data['name'] ?? 'Emergency Contact',
          'phone': data['phone'] as String,
          'id': doc.id,
        };
      }).toList();

      final contactCount = contacts.length;

      if (contactCount == 0) {
        throw Exception("No emergency contacts enabled. Add contacts first.");
      }

      // 4️⃣ CREATE SOS ALERT IN FIRESTORE
      final alertRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .doc();

      final alertId = alertRef.id;

      final alertData = {
        'id': alertId,
        'type': 'SOS',
        'status': 'sent',
        'message': '🚨 Manual SOS triggered from safety app',
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'googleMapsLink':
            'https://maps.google.com/?q=${location.latitude},${location.longitude}',
        'contacts': contacts,
        'contactCount': contactCount,
        'timestamp': DateTime.now().toIso8601String(),
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };

      await alertRef.set(alertData);

      // 5️⃣ UPDATE REAL-TIME STATUS
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('status')
          .doc('current')
          .update({
            'sosActive': true,
            'lastSosTime': Timestamp.now(),
            'lastSosLocation': GeoPoint(location.latitude, location.longitude),
            'currentAlertId': alertId,
          });

      // 6️⃣ PREPARE SMS FOR ALL CONTACTS
      final String message =
          """
🚨 SOS ALERT - EMERGENCY!

Child has triggered an SOS alert and needs immediate assistance.

📍 Location: https://maps.google.com/?q=${location.latitude},${location.longitude}
⏰ Time: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}
📱 App: Student Safety System

Please respond immediately.
""";

      // 7️⃣ SEND SMS TO ALL CONTACTS
      final smsSent = await _sendSMSToAllContacts(contacts, message, context);

      // 8️⃣ UPDATE ALERT WITH SMS STATUS
      await alertRef.update({'smsSent': smsSent, 'smsSentAt': Timestamp.now()});

      // 9️⃣ SHOW SUCCESS MESSAGE
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  smsSent
                      ? "✅ SOS sent to $contactCount emergency contacts"
                      : "⚠️ SOS saved - Open SMS app manually",
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: smsSent ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() => _sosLoading = false);
    } catch (e) {
      setState(() => _sosLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "SOS Failed: ${e.toString().replaceAll('Exception:', '').trim()}",
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 📱 FUNCTION TO SEND SMS TO ALL CONTACTS
  Future<bool> _sendSMSToAllContacts(
    List<Map<String, dynamic>> contacts,
    String message,
    BuildContext context,
  ) async {
    try {
      // Encode message for URL
      final encodedMessage = Uri.encodeComponent(message);

      // Get all phone numbers
      final phoneNumbers = contacts.map((c) => c['phone'] as String).toList();

      if (phoneNumbers.isEmpty) return false;

      // Clean phone numbers (remove spaces, dashes, keep +)
      final cleanNumbers = phoneNumbers.map((phone) {
        return phone.replaceAll(RegExp(r'[^0-9+]'), '');
      }).toList();

      // Join numbers with commas for multiple recipients
      final numbersString = cleanNumbers.join(',');

      // Create SMS URI with multiple recipients
      final uri = Uri.parse('sms:$numbersString?body=$encodedMessage');

      // Launch SMS app with ALL contacts
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);

        // Show which contacts were included
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "📱 SMS app opened",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "All ${contacts.length} contacts added to message",
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (contacts.length <= 3) ...[
                    const SizedBox(height: 4),
                    ...contacts.map(
                      (contact) =>
                          Text("• ${contact['name']}: ${contact['phone']}"),
                    ),
                  ],
                ],
              ),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return true;
      } else {
        // Fallback: Try first contact
        return await _sendToFirstContact(contacts.first, message, context);
      }
    } catch (e) {
      debugPrint("Error sending SMS to all contacts: $e");
      // Try first contact as fallback
      if (contacts.isNotEmpty) {
        return await _sendToFirstContact(contacts.first, message, context);
      }
      return false;
    }
  }

  // 📱 FALLBACK: SEND TO FIRST CONTACT
  Future<bool> _sendToFirstContact(
    Map<String, dynamic> contact,
    String message,
    BuildContext context,
  ) async {
    try {
      final encodedMessage = Uri.encodeComponent(message);
      final cleanPhone = (contact['phone'] as String).replaceAll(
        RegExp(r'[^0-9+]'),
        '',
      );
      final uri = Uri.parse('sms:$cleanPhone?body=$encodedMessage');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("📱 SMS opened for ${contact['name']}"),
              backgroundColor: Colors.blue,
            ),
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Student Safety"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('device')
                  .doc('status')
                  .snapshots(),
              builder: (context, deviceSnap) {
                bool deviceOnline = true;
                Timestamp? lastSeen;

                if (deviceSnap.hasData && deviceSnap.data!.exists) {
                  final data = deviceSnap.data!.data() as Map<String, dynamic>;
                  lastSeen = data['lastSeen'];
                  deviceOnline = _isDeviceOnline(lastSeen);
                }

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('status')
                      .doc('current')
                      .snapshots(),
                  builder: (context, snapshot) {
                    bool isInside = true;
                    bool sosActive = false;
                    double? childLat;
                    double? childLng;

                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      isInside = data['insideGeofence'] ?? true;
                      sosActive = data['sosActive'] ?? false;
                      // Try to get last known child location from status doc
                      final loc = data['lastLocation'];
                      if (loc is GeoPoint) {
                        childLat = loc.latitude;
                        childLng = loc.longitude;
                      } else if (loc is Map) {
                        childLat = (loc['latitude'] as num?)?.toDouble();
                        childLng = (loc['longitude'] as num?)?.toDouble();
                      }
                    }

                    return Stack(
                      children: [
                        SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            8,
                          ), // Reduced bottom padding
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _statusCard(isInside),

                              // 🆕 DEVICE ONLINE STATUS BADGE
                              if (!deviceOnline) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.orange),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.wifi_off,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        "Device Offline",
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              _miniMap(uid, isInside),
                              const SizedBox(height: 16), // Reduced from 20
                              // 🚨 SOS BUTTON - SIMPLIFIED
                              Container(
                                height: 58, // Fixed height
                                child: _sosButton(uid, isInside, deviceOnline),
                              ),
                              const SizedBox(height: 12),

                              // 🚧 Geofence breach card
                              if (!isInside) ...[
                                GeofenceAlertCard(lat: childLat, lng: childLng),
                                const SizedBox(height: 12),
                              ],
                              // 🤖 Fall detection card (streams itself from Firestore)
                              const FallAlertCard(),
                              const SizedBox(height: 12),

                              _groupedActions(context),
                              const SizedBox(height: 12), // Reduced from 16

                              _batterySummaryCard(context, deviceOnline),

                              // Bottom safe area
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),

                        // LOADING OVERLAY
                        if (_sosLoading)
                          Container(
                            color: Colors.black.withOpacity(0.3),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.red,
                                      ),
                                      strokeWidth: 4,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "Sending SOS Alert",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(uid)
                                          .collection('emergency_contacts')
                                          .where(
                                            'receiveAlerts',
                                            isEqualTo: true,
                                          )
                                          .snapshots(),
                                      builder: (context, snapshot) {
                                        final count = snapshot.hasData
                                            ? snapshot.data!.docs.length
                                            : 0;
                                        return Text(
                                          "Sending to $count emergency contact${count != 1 ? 's' : ''}...",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🟢 / 🔴 STATUS CARD
  Widget _statusCard(bool isInside) {
    return Container(
      padding: const EdgeInsets.all(12), // Reduced padding
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          isInside ? Icons.verified : Icons.warning,
          color: isInside ? Colors.green : Colors.red,
          size: 28, // Reduced size
        ),
        title: const Text(
          "Child Status",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14, // Reduced font size
          ),
        ),
        subtitle: Text(
          isInside ? "🟢 Safe" : "⚠️ Outside safe zone",
          style: const TextStyle(fontSize: 12), // Reduced font size
        ),
      ),
    );
  }

  // 🗺️ MINI MAP
  Widget _miniMap(String uid, bool isInside) {
    return Container(
      height: 160, // Further reduced
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInside ? Colors.green : Colors.red,
          width: 2, // Reduced border width
        ),
      ),
      child: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('student').onValue,
        builder: (context, snapshot) {
          LatLng childLocation = const LatLng(10.039298, 76.325);

          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final val = snapshot.data!.snapshot.value;
            if (val is Map) {
              final data = Map<String, dynamic>.from(val);
              double? lat = _toDouble(data['latitude'] ?? data['lat']);
              double? lng = _toDouble(data['longitude'] ?? data['lng']);
              if (lat != null && lng != null && lat != 0 && lng != 0) {
                childLocation = LatLng(lat, lng);
              }
            }
          }

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  GoogleMap(
                    key: ValueKey(childLocation),
                    initialCameraPosition: CameraPosition(
                      target: childLocation,
                      zoom: 16,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId("child"),
                        position: childLocation,
                      ),
                    },
                    liteModeEnabled: true,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                      ), // Reduced
                      color: Colors.black.withOpacity(0.55),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.open_in_full,
                            color: Colors.white,
                            size: 14,
                          ), // Reduced
                          SizedBox(width: 4),
                          Text(
                            "Tap to expand",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11, // Reduced
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 🚨 SOS BUTTON - ULTRA SIMPLIFIED
  Widget _sosButton(String uid, bool isInside, bool deviceOnline) {
    return ScaleTransition(
      scale: isInside ? const AlwaysStoppedAnimation(1) : _pulseController,
      child: GestureDetector(
        onLongPress: () => _triggerSOS(context, uid),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.white,
                    size: 22, // Reduced
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "HOLD FOR SOS",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14, // Reduced
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        "Sends SMS to all contacts",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9, // Reduced
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 📦 GROUPED ACTIONS - COMPACT
  Widget _groupedActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12), // Reduced
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _compactActionTile(
            context,
            icon: Icons.contacts,
            title: "Emergency Contacts",
            screen: const EmergencyContactsScreen(),
          ),
          const Divider(height: 12),
          _compactActionTile(
            context,
            icon: Icons.timeline,
            title: "Location History",
            screen: const LocationHistoryScreen(),
          ),
          const Divider(height: 12),
          _compactActionTile(
            context,
            icon: Icons.history,
            title: "Alert History",
            screen: const AlertHistoryScreen(),
          ),
        ],
      ),
    );
  }

  Widget _compactActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget screen,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      },
    );
  }

  // 🔋 BATTERY - COMPACT
  Widget _batterySummaryCard(BuildContext context, bool deviceOnline) {
    return Container(
      padding: const EdgeInsets.all(12), // Reduced
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(
          deviceOnline ? Icons.battery_full : Icons.battery_alert,
          color: deviceOnline ? Colors.green : Colors.orange,
          size: 28, // Reduced
        ),
        title: const Text(
          "Device Status",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          deviceOnline ? "Connected • Battery 92%" : "Device offline",
          style: TextStyle(
            fontSize: 11,
            color: deviceOnline ? Colors.grey[600] : Colors.orange,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BatteryScreen()),
          );
        },
      ),
    );
  }
}
