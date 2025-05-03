import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

// Data model for the entire dashboard summary fetched from Firestore
class DashboardAnalyticsData {
  final Timestamp? lastUpdated;
  final PeopleDetectedData? peopleDetected;
  final IncidentData? loneWomenIncidents;
  final IncidentData? womenSurroundedIncidents;
  final SosGestureData? sosGestures;
  final HotspotData? incidentHotspots;

  DashboardAnalyticsData({
    this.lastUpdated,
    this.peopleDetected,
    this.loneWomenIncidents,
    this.womenSurroundedIncidents,
    this.sosGestures,
    this.incidentHotspots,
  });

  factory DashboardAnalyticsData.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    return DashboardAnalyticsData(
      lastUpdated: data['lastUpdated'] as Timestamp?,
      peopleDetected:
          data['peopleDetected'] != null
              ? PeopleDetectedData.fromMap(
                data['peopleDetected'] as Map<String, dynamic>,
              )
              : null,
      loneWomenIncidents:
          data['loneWomenIncidents'] != null
              ? IncidentData.fromMap(
                data['loneWomenIncidents'] as Map<String, dynamic>,
              )
              : null,
      womenSurroundedIncidents:
          data['womenSurroundedIncidents'] != null
              ? IncidentData.fromMap(
                data['womenSurroundedIncidents'] as Map<String, dynamic>,
              )
              : null,
      sosGestures:
          data['sosGestures'] != null
              ? SosGestureData.fromMap(
                data['sosGestures'] as Map<String, dynamic>,
              )
              : null,
      incidentHotspots:
          data['incidentHotspots'] != null
              ? HotspotData.fromMap(
                data['incidentHotspots'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

// Sub-models for each section

class PeopleDetectedData {
  final int? total;
  final num? womenPercent; // Use num for flexibility (int or double)
  final num? menPercent;
  final Map<String, num>? monthlyCounts; // e.g., {"Jan": 100, "Feb": 120}

  PeopleDetectedData({
    this.total,
    this.womenPercent,
    this.menPercent,
    this.monthlyCounts,
  });

  factory PeopleDetectedData.fromMap(Map<String, dynamic> map) {
    return PeopleDetectedData(
      total: map['total'] as int?,
      womenPercent: map['womenPercent'] as num?,
      menPercent: map['menPercent'] as num?,
      monthlyCounts: (map['monthlyCounts'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as num),
      ),
    );
  }
}

class IncidentData {
  final int? lastHour;
  final Map<String, Map<String, num>>?
  monthlyTrend; // e.g., {"series1": {"Jan": 10, ...}, "series2": {"Jan": 5, ...}}

  IncidentData({this.lastHour, this.monthlyTrend});

  factory IncidentData.fromMap(Map<String, dynamic> map) {
    // Deep conversion for nested maps
    Map<String, Map<String, num>>? trendData;
    if (map['monthlyTrend'] != null) {
      trendData = (map['monthlyTrend'] as Map<String, dynamic>).map(
        (seriesKey, monthlyMap) => MapEntry(
          seriesKey,
          (monthlyMap as Map<String, dynamic>).map(
            (monthKey, value) => MapEntry(monthKey, value as num),
          ),
        ),
      );
    }

    return IncidentData(
      lastHour: map['lastHour'] as int?,
      monthlyTrend: trendData,
    );
  }
}

class SosGestureData {
  final int? detectedLastHour;
  final Map<String, num>? distribution; // e.g., {"A": 10, "B": 5}

  SosGestureData({this.detectedLastHour, this.distribution});

  factory SosGestureData.fromMap(Map<String, dynamic> map) {
    return SosGestureData(
      detectedLastHour: map['detectedLastHour'] as int?,
      distribution: (map['distribution'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as num),
      ),
    );
  }
}

class HotspotData {
  final List<HotspotLocation>? topLocations;

  HotspotData({this.topLocations});

  factory HotspotData.fromMap(Map<String, dynamic> map) {
    List<HotspotLocation>? locations;
    if (map['topLocations'] != null) {
      locations =
          (map['topLocations'] as List<dynamic>)
              .map(
                (item) => HotspotLocation.fromMap(item as Map<String, dynamic>),
              )
              .toList();
    }
    return HotspotData(topLocations: locations);
  }
}

class HotspotLocation {
  final String? name;
  final int? countLastMonth;

  HotspotLocation({this.name, this.countLastMonth});

  factory HotspotLocation.fromMap(Map<String, dynamic> map) {
    return HotspotLocation(
      name: map['name'] as String?,
      countLastMonth: map['countLastMonth'] as int?,
    );
  }
}

// Helper function to get month index (0=Jan, 1=Feb, ...)
int getMonthIndex(String month) {
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months.indexOf(month);
}

// Helper function to get month abbreviation from index
String getMonthAbbreviation(int index) {
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return index >= 0 && index < months.length ? months[index] : '';
}

// Helper to generate chart spots from monthly data map
List<FlSpot> generateSpots(Map<String, num>? data, [int maxMonths = 6]) {
  if (data == null) return [];
  List<FlSpot> spots = [];
  List<String> sortedMonths =
      data.keys.toList()
        ..sort((a, b) => getMonthIndex(a).compareTo(getMonthIndex(b)));

  for (String month in sortedMonths) {
    int index = getMonthIndex(month);
    if (index >= 0 && index < maxMonths) {
      // Limit to specified months (e.g., Jan-Jun)
      spots.add(FlSpot(index.toDouble(), data[month]!.toDouble()));
    }
  }
  return spots;
}
