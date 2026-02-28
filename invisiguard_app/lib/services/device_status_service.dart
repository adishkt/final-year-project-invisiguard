import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceStatusService {
  static const int offlineThresholdSeconds = 60;

  static bool isDeviceOnline(Timestamp lastSeen) {
    final now = DateTime.now();
    final last = lastSeen.toDate();

    final diff = now.difference(last).inSeconds;
    return diff <= offlineThresholdSeconds;
  }
}
