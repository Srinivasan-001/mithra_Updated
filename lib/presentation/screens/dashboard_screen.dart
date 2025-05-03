import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

// --- Data Models (Simplified based on screenshots) ---

// Helper to get month abbreviation
String getMonthAbbreviation(int month) {
  if (month >= 1 && month <= 12) {
    return DateFormat.MMM().format(DateTime(2024, month)); // Use a dummy year
  }
  return '';
}

// Helper to generate FlSpot list from map
List<FlSpot> generateSpots(Map<String, dynamic>? data) {
  if (data == null) return [];
  List<FlSpot> spots = [];
  data.forEach((key, value) {
    // Assuming key is month number as string ('1', '2', ... '12')
    final month = int.tryParse(key);
    final count = (value as num?)?.toDouble();
    if (month != null && count != null) {
      spots.add(FlSpot(month.toDouble(), count));
    }
  });
  spots.sort((a, b) => a.x.compareTo(b.x)); // Sort by month
  return spots;
}

class GenderData {
  final double womenPercent;
  final double menPercent;
  final Map<String, dynamic>?
  monthlyDistribution; // e.g., {'Jan': 40, 'Feb': 50, ...}

  GenderData({
    required this.womenPercent,
    required this.menPercent,
    this.monthlyDistribution,
  });

  factory GenderData.fromMap(Map<String, dynamic>? map) {
    if (map == null) return GenderData(womenPercent: 0, menPercent: 0);
    return GenderData(
      womenPercent: (map['womenPercent'] as num?)?.toDouble() ?? 0.0,
      menPercent: (map['menPercent'] as num?)?.toDouble() ?? 0.0,
      monthlyDistribution: map['monthlyDistribution'] as Map<String, dynamic>?,
    );
  }
}

class IncidentTrendData {
  final int currentIncidents;
  final Map<String, dynamic>? monthlyTrend1; // e.g., {'1': 50, '2': 60, ...}
  final Map<String, dynamic>? monthlyTrend2; // Optional second series

  IncidentTrendData({
    required this.currentIncidents,
    this.monthlyTrend1,
    this.monthlyTrend2,
  });

  factory IncidentTrendData.fromMap(Map<String, dynamic>? map) {
    if (map == null) return IncidentTrendData(currentIncidents: 0);
    return IncidentTrendData(
      currentIncidents: (map['currentIncidents'] as num?)?.toInt() ?? 0,
      monthlyTrend1: map['monthlyTrend1'] as Map<String, dynamic>?,
      monthlyTrend2: map['monthlyTrend2'] as Map<String, dynamic>?,
    );
  }
}

class SosAlertData {
  final int alertCount;
  // Add more fields if needed based on screenshot 3's heatmap

  SosAlertData({required this.alertCount});

  factory SosAlertData.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SosAlertData(alertCount: 0);
    return SosAlertData(alertCount: (map['alertCount'] as num?)?.toInt() ?? 0);
  }
}

class HotspotData {
  final String locationName;
  final int incidentCount;

  HotspotData({required this.locationName, required this.incidentCount});

  factory HotspotData.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return HotspotData(locationName: 'Unknown', incidentCount: 0);
    }
    return HotspotData(
      locationName: map['locationName'] as String? ?? 'Unknown',
      incidentCount: (map['incidentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

// --- Main Dashboard Screen ---

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Logger _logger = Logger();
  DateTimeRange? _selectedDateRange;

  // Placeholder Data (replace with actual data fetching logic)
  
  final GenderData _genderData = GenderData(
    womenPercent: 45,
    menPercent: 55,
    monthlyDistribution: {
      'Jan': 30,
      'Feb': 45,
      'Mar': 60,
      'Apr': 50,
      'May': 70,
      'Jun': 65,
    },
  );

  final IncidentTrendData _loneWomanData = IncidentTrendData(
    currentIncidents: 12,
    monthlyTrend1: {
      '1': 50,
      '2': 60,
      '3': 40,
      '4': 150,
      '5': 100,
      '6': 180,
    }, // Blue line
    monthlyTrend2: {
      '1': 60,
      '2': 50,
      '3': 100,
      '4': 180,
      '5': 90,
      '6': 120,
    }, // Red line
  );

  final IncidentTrendData _womanSurroundedData = IncidentTrendData(
    currentIncidents: 7,
    monthlyTrend1: {
      '1': 105,
      '2': 155,
      '3': 125,
      '4': 145,
      '5': 115,
      '6': 75,
    }, // Bar chart data
  );

  final SosAlertData _sosData = SosAlertData(alertCount: 3);

  final List<HotspotData> _hotspotData = [
    HotspotData(locationName: 'Main Street', incidentCount: 12),
    HotspotData(locationName: 'Park Avenue', incidentCount: 9),
    HotspotData(locationName: 'Elm Street', incidentCount: 8),
    HotspotData(locationName: 'Oak Street', incidentCount: 7),
    // Add more if needed
  ];

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    // TODO: Initialize actual data fetching based on _selectedDateRange
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _logger.i(
        'Selected date range: ${_selectedDateRange?.start} - ${_selectedDateRange?.end}',
      );
      // TODO: Trigger data refresh based on the new date range
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine screen size for responsive layout
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1200 ? 3 : (screenWidth > 600 ? 2 : 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Women\'s Safety Analytics'),
        actions: [
          // Placeholder buttons for 'Today', 'This Month'
          TextButton(onPressed: () {}, child: const Text('Today')),
          TextButton(onPressed: () {}, child: const Text('This Month')),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Select Date Range',
            onPressed: _selectDateRange,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // TODO: Implement actual data refresh logic
          _logger.i('Pull to refresh triggered');
          await Future.delayed(
            const Duration(seconds: 1),
          ); // Simulate network delay
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (_selectedDateRange != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Displaying data for: ${DateFormat.yMd().format(_selectedDateRange!.start)} - ${DateFormat.yMd().format(_selectedDateRange!.end)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics:
                    const NeverScrollableScrollPhysics(), // Disable GridView's own scrolling
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio:
                    crossAxisCount == 1 ? 1.6 : 1.3, // Adjusted aspect ratio for better responsiveness
                children: [
                  _buildGenderDistributionCard(_genderData),
                  _buildIncidentCard(
                    title: 'Lone Women at Night',
                    data: _loneWomanData,
                    chartType: ChartType.line,
                  ),
                  _buildIncidentCard(
                    title: 'Women Surrounded by Men',
                    data: _womanSurroundedData,
                    chartType: ChartType.bar,
                  ),
                  _buildSosAlertsCard(_sosData),
                  _buildHotspotsCard(_hotspotData),
                  _buildIncidentReportsCard(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Card Builder Widgets ---

  Widget _buildDashboardCard({
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) Icon(icon, size: 18, color: Colors.grey[700]),
                if (icon != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: child), // Make child expand
          ],
        ),
      ),
    );
  }

  Widget _buildGenderDistributionCard(GenderData data) {
    final List<PieChartSectionData> sections = [
      PieChartSectionData(
        color: Colors.blue,
        value: data.womenPercent,
        title: '${data.womenPercent.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      PieChartSectionData(
        color: Colors.lightBlueAccent,
        value: data.menPercent,
        title: '${data.menPercent.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ];

    // Placeholder for month labels around the pie chart (complex to implement accurately)
    // For simplicity, we'll just show the percentages.

    return _buildDashboardCard(
      title: 'Gender Distribution',
      icon: Icons.people_outline, // Example icon
      child: Center(
        child: SizedBox(
          width: 150, // Constrain pie chart size
          height: 150,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 30,
              sectionsSpace: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentCard({
    required String title,
    required IncidentTrendData data,
    required ChartType chartType,
    IconData? icon,
  }) {
    final series1Spots = generateSpots(data.monthlyTrend1);
    final series2Spots = generateSpots(data.monthlyTrend2);

    double maxY = 10;
    if (series1Spots.isNotEmpty || series2Spots.isNotEmpty) {
      double max1 =
          series1Spots.isNotEmpty
              ? series1Spots.map((s) => s.y).reduce((a, b) => a > b ? a : b)
              : 0;
      double max2 =
          series2Spots.isNotEmpty
              ? series2Spots.map((s) => s.y).reduce((a, b) => a > b ? a : b)
              : 0;
      maxY = (max1 > max2 ? max1 : max2) * 1.2;
      if (maxY < 10) maxY = 10; // Ensure a minimum height
    }

    Widget chartWidget;
    if (chartType == ChartType.line) {
      chartWidget = LineChart(
        LineChartData(
          maxY: maxY,
          minY: 0,
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(sideTitles: _bottomTitles),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY / 4,
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            if (series1Spots.isNotEmpty)
              LineChartBarData(
                spots: series1Spots,
                isCurved: true,
                color: Colors.blue,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            if (series2Spots.isNotEmpty)
              LineChartBarData(
                spots: series2Spots,
                isCurved: true,
                color: Colors.red,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
          ],
        ),
      );
    } else {
      // Bar Chart
      chartWidget = BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(sideTitles: _bottomTitles),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY / 4,
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups:
              series1Spots.map((spot) {
                return BarChartGroupData(
                  x: spot.x.toInt(),
                  barRods: [
                    BarChartRodData(
                      toY: spot.y,
                      color: Colors.blue,
                      width: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }).toList(),
        ),
      );
    }

    return _buildDashboardCard(
      title: title,
      icon:
          icon ??
          (chartType == ChartType.line ? Icons.show_chart : Icons.bar_chart),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data.currentIncidents}',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (chartType ==
              ChartType
                  .line) // Show 'Incidents in last hour' only for line chart cards?
            Text(
              'Incidents in the last hour',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Expanded(child: chartWidget),
        ],
      ),
    );
  }

  Widget _buildSosAlertsCard(SosAlertData data) {
    return _buildDashboardCard(
      title: 'SOS Gestures',
      icon: Icons.sos,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${data.alertCount}',
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('Alerts', style: Theme.of(context).textTheme.titleMedium),
            // TODO: Add heatmap/bar from screenshot 3 if needed
          ],
        ),
      ),
    );
  }

  Widget _buildHotspotsCard(List<HotspotData> data) {
    return _buildDashboardCard(
      title: 'Safety Hotspots',
      icon: Icons.location_pin,
      child:
          data.isEmpty
              ? const Center(child: Text('No hotspot data available.'))
              : ListView.builder(
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final hotspot = data[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.pin_drop_outlined, size: 20),
                    title: Text(
                      hotspot.locationName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Text('${hotspot.incidentCount} incidents'),
                  );
                },
              ),
    );
  }

  Widget _buildIncidentReportsCard() {
    return _buildDashboardCard(
      title: 'Incident Reports',
      icon: Icons.description_outlined,
      child: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('View Reports'),
          onPressed: () {
            // TODO: Implement navigation to reports screen
            _logger.i('View Reports button pressed');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Report viewing not implemented yet.'),
              ),
            );
          },
        ),
      ),
    );
  }

  // Helper for bottom axis titles (Months)
  SideTitles get _bottomTitles => SideTitles(
    showTitles: true,
    reservedSize: 24,
    getTitlesWidget: (value, meta) {
      String text = getMonthAbbreviation(value.toInt());
      return SideTitleWidget(
        space: 4,
        meta: meta,
        child: Text(text, style: const TextStyle(fontSize: 10)),
      );
    },
  );
}

enum ChartType { line, bar, pie }
