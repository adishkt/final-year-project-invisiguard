
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SmsService {
  static Future<bool> sendSOS({
    required List<String> phones,
    required LatLng location,
  }) async {
    try {
      // Create Google Maps link
      final mapsLink = "https://maps.google.com/?q=${location.latitude},${location.longitude}";
      
      // Create message
      final message = Uri.encodeComponent("""
🚨 SOS ALERT - Child needs immediate help!
Location: $mapsLink
Time: ${DateTime.now().toString().substring(11, 16)}
Please check safety app for live tracking.""");
      
      bool atLeastOneSent = false;
      
      for (final phone in phones) {
        // Clean phone number
        final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
        
        // Create SMS URI
        final uri = Uri.parse('sms:$cleanPhone?body=$message');
        
        // Launch system SMS app
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          atLeastOneSent = true;
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
      
      return atLeastOneSent;
    } catch (e) {
      print("SMS Launch Error: $e");
      return false;
    }
  }
}