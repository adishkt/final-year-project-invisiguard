// lib/services/auto_sms_service.dart
import 'package:flutter/services.dart';

class AutoSmsService {
  static const platform = MethodChannel('com.example.invisiguard/sms');

  static Future<bool> sendAutoSMS(String phone, String message) async {
    try {
      final result = await platform.invokeMethod('sendSMS', {
        'phone': phone,
        'message': message,
      });
      return result == true;
    } on PlatformException catch (e) {
      print("Auto SMS failed: ${e.message}");
      return false;
    }
  }
}