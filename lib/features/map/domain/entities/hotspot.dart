import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Hotspot {
  final String id;
  final String name;
  final LatLng position;
  final double radius; // Radius in meters
  // Add other relevant details if needed, e.g., incident type, severity

  Hotspot({
    required this.id,
    required this.name,
    required this.position,
    required this.radius,
  });

  factory Hotspot.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    GeoPoint geoPoint = data['location'] ?? const GeoPoint(0, 0); // Default to (0,0) if null
    return Hotspot(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Hotspot',
      position: LatLng(geoPoint.latitude, geoPoint.longitude),
      radius: (data['radius'] as num?)?.toDouble() ?? 50.0, // Default radius 50m
    );
  }
}

