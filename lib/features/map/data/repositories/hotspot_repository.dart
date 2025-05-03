import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../../domain/entities/hotspot.dart';

class HotspotRepository {
  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  HotspotRepository({FirebaseFirestore? firestore}) 
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Fetches hotspots as a stream for real-time updates
  Stream<List<Hotspot>> getHotspotsStream() {
    // TODO: Add error handling and potentially query limits/filters
    // IMPORTANT: Ensure the user adds Firebase config files before running.
    try {
      return _firestore.collection('hotspots').snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => Hotspot.fromFirestore(doc)).toList();
      });
    } catch (e) {
      _logger.e("Error fetching hotspots stream: $e");
      // Return an empty stream or rethrow, depending on desired error handling
      return Stream.value([]); 
    }
  }

  // Alternative: Fetch hotspots once as a future
  Future<List<Hotspot>> getHotspotsOnce() async {
    // IMPORTANT: Ensure the user adds Firebase config files before running.
    try {
      final snapshot = await _firestore.collection('hotspots').get();
      return snapshot.docs.map((doc) => Hotspot.fromFirestore(doc)).toList();
    } catch (e) {
      _logger.e("Error fetching hotspots once: $e");
      return []; // Return empty list on error
    }
  }

  // TODO: Add methods for adding/updating/deleting hotspots if needed
}

