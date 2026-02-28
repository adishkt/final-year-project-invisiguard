import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'map_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationHistoryScreen extends StatelessWidget {
  const LocationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text("Location History")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('location_history')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No location history yet"));
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;

              final lat = data['latitude'];
              final lng = data['longitude'];
              final time = (data['timestamp'] as Timestamp).toDate();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.blue),
                  title: Text("Lat: $lat, Lng: $lng"),
                  subtitle: Text(
                    "${time.hour}:${time.minute.toString().padLeft(2, '0')} • "
                    "${time.day}/${time.month}/${time.year}",
                  ),
                  trailing: const Icon(Icons.map),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MapScreen(initialTarget: LatLng(lat, lng)),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
