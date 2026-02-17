import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/call_recording.dart';
import '../providers/call_recordings_provider.dart';
import 'package:po_processor/presentation/widgets/ai_disclaimer.dart';

/// Comprehensive dashboard showing all call analytics and insights
class ComprehensiveCallDashboard extends StatelessWidget {
  final CallAnalysis? singleCallAnalysis;
  final bool showAggregateMetrics;

  const ComprehensiveCallDashboard({
    super.key,
    this.singleCallAnalysis,
    this.showAggregateMetrics = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showAggregateMetrics) {
      return Consumer<CallRecordingsProvider>(
        builder: (context, provider, _) {
          final allRecordings = provider.recordings
              .map((r) => provider.getRecordingWithData(r.id))
              .where((r) => r?.analysis != null)
              .whereType<CallRecording>()
              .toList();

          if (allRecordings.isEmpty) {
            return _buildEmptyState();
          }

          return _buildAggregateDashboard(context, allRecordings);
        },
      );
    }

    if (singleCallAnalysis == null) {
      return _buildEmptyState();
    }

    return _buildSingleCallDashboard(context, singleCallAnalysis!);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Analytics Available',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Analyze calls to view insights',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleCallDashboard(
    BuildContext context,
    CallAnalysis analysis,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards Row
          _buildKPICards(analysis),
          const SizedBox(height: 24),

          // Sentiment Trend Chart (removed talk time ratio)
          _buildSentimentTrendChart(analysis),
          const SizedBox(height: 24),

          // Topics & Agent Performance Row
          Row(
            children: [
              Expanded(child: _buildTopicsBarChart(analysis)),
              const SizedBox(width: 16),
              Expanded(child: _buildAgentPerformanceRadar(analysis)),
            ],
          ),
          const SizedBox(height: 24),

          // Loudness Heat Map
          if (analysis.loudnessTrend.isNotEmpty)
            _buildLoudnessHeatMap(analysis),
          const SizedBox(height: 24),

          // Word Cloud
          if (analysis.wordCloud.isNotEmpty) _buildWordCloud(analysis),
          const SizedBox(height: 24),

          // AI Disclaimer
          const AIDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildAggregateDashboard(
    BuildContext context,
    List<CallRecording> recordings,
  ) {
    final metrics = _calculateAggregateMetrics(recordings);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Call Analytics Dashboard',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Top KPI Cards
          _buildAggregateKPICards(metrics),
          const SizedBox(height: 24),

          // Charts Row 1
          Row(
            children: [
              Expanded(child: _buildTotalCallsChart(recordings)),
              const SizedBox(width: 16),
              Expanded(child: _buildCallsByLanguageChart(recordings)),
            ],
          ),
          const SizedBox(height: 24),

          // Charts Row 2
          Row(
            children: [
              Expanded(child: _buildCallsByDepartmentChart(recordings)),
              const SizedBox(width: 16),
              Expanded(child: _buildCallsByWeekChart(recordings)),
            ],
          ),
          const SizedBox(height: 24),

          // Duration Distribution
          _buildDurationDistributionChart(recordings),
          const SizedBox(height: 24),

          // Talk Time Impact on Sentiment
          _buildTalkTimeSentimentImpact(recordings),
          const SizedBox(height: 24),

          // Agent Performance Comparison
          _buildAgentPerformanceComparison(recordings),
          const SizedBox(height: 24),

          // Calls Status Distribution
          _buildCallsStatusChart(recordings),
          const SizedBox(height: 24),

          // First Call Resolution Rate
          _buildFirstCallResolutionChart(recordings),
          const SizedBox(height: 24),

          // AI Disclaimer
          const AIDisclaimer(),
        ],
      ),
    );
  }

  // KPI Cards for Single Call
  Widget _buildKPICards(CallAnalysis analysis) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Sentiment',
                analysis.sentimentScore.overall,
                _getSentimentColor(analysis.sentimentScore.overall),
                Icons.sentiment_satisfied,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                'Sentiment Score',
                '${(analysis.sentimentScore.score * 100).toStringAsFixed(0)}%',
                _getSentimentColor(analysis.sentimentScore.overall),
                Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                'Agent Score',
                '${analysis.agentScore.rating}/10',
                _getScoreColor(analysis.agentScore.rating.toDouble()),
                Icons.star,
              ),
            ),
          ],
        ),
        // const SizedBox(height: 12),
        // Row(
        //   children: [
        //     Expanded(
        //       child: _buildKPICard(
        //         'Agent Talk Time',
        //         '${analysis.agentTalkSeconds.toStringAsFixed(0)}s',
        //         Colors.blue,
        //         Icons.mic,
        //       ),
        //     ),
        //     const SizedBox(width: 12),
        //     Expanded(
        //       child: _buildKPICard(
        //         'Customer Talk Time',
        //         '${analysis.customerTalkSeconds.toStringAsFixed(0)}s',
        //         Colors.green,
        //         Icons.person,
        //       ),
        //     ),
        //     const SizedBox(width: 12),
        //     Expanded(
        //       child: _buildKPICard(
        //         'Total Duration',
        //         '${(analysis.agentTalkSeconds + analysis.customerTalkSeconds).toStringAsFixed(0)}s',
        //         Colors.purple,
        //         Icons.timer,
        //       ),
        //     ),
        //   ],
        // ),
        if (analysis.firstCallResolution != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildKPICard(
                  'First Call Resolution',
                  analysis.firstCallResolution == true ? 'Yes' : 'No',
                  analysis.firstCallResolution == true
                      ? Colors.green
                      : Colors.orange,
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKPICard(
                  'Language',
                  analysis.detectedLanguage ?? 'Unknown',
                  Colors.indigo,
                  Icons.language,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKPICard(
                  'Topics Count',
                  '${analysis.topics.length}',
                  Colors.teal,
                  Icons.category,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Aggregate KPI Cards
  Widget _buildAggregateKPICards(AggregateMetrics metrics) {
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            'Total Calls',
            metrics.totalCalls.toString(),
            Colors.indigo,
            Icons.phone_in_talk,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            'Avg Agent Talk',
            '${metrics.avgAgentTalkSec.toStringAsFixed(0)}s',
            Colors.blue,
            Icons.mic,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            'Avg Customer Talk',
            '${metrics.avgCustomerTalkSec.toStringAsFixed(0)}s',
            Colors.green,
            Icons.person,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKPICard(
            'FCR Rate',
            '${(metrics.firstCallResolutionRate * 100).toStringAsFixed(1)}%',
            Colors.orange,
            Icons.check_circle,
          ),
        ),
      ],
    );
  }

  Widget _buildKPICard(String label, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sentiment Trend Line Chart
  Widget _buildSentimentTrendChart(CallAnalysis analysis) {
    // Ensure we always have data points for the chart
    final dataPoints = analysis.sentimentTrend.dataPoints;
    List<FlSpot> spots;

    if (dataPoints.isEmpty) {
      // If no data points, create default points to show the chart
      spots = [
        const FlSpot(0.0, 0.0),
        const FlSpot(10.0, 0.0),
        const FlSpot(20.0, 0.0),
      ];
    } else if (dataPoints.length == 1) {
      // If only one point, create additional points for visibility
      final point = dataPoints.first;
      spots = [
        FlSpot(point.timestamp, point.sentiment),
        FlSpot(point.timestamp + 10, point.sentiment),
        FlSpot(point.timestamp + 20, point.sentiment),
      ];
    } else {
      spots = dataPoints
          .map((point) => FlSpot(point.timestamp, point.sentiment))
          .toList();
    }

    // Calculate min/max for better chart display
    final sentimentValues = spots.map((spot) => spot.y).toList();
    final minY = sentimentValues.isEmpty
        ? -1.0
        : (sentimentValues.reduce((a, b) => a < b ? a : b) - 0.2).clamp(
            -1.0,
            1.0,
          );
    final maxY = sentimentValues.isEmpty
        ? 1.0
        : (sentimentValues.reduce((a, b) => a > b ? a : b) + 0.2).clamp(
            -1.0,
            1.0,
          );
    final maxX = spots.isEmpty
        ? 100.0
        : spots.map((spot) => spot.x).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sentiment Trend',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}s',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: dataPoints.length <= 3, // Show dots if few points
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.indigo,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.indigo.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: maxX > 0 ? maxX : 100,
                ),
              ),
            ),
            if (dataPoints.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No sentiment data available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Topics Bar Chart
  Widget _buildTopicsBarChart(CallAnalysis analysis) {
    if (analysis.topics.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Topics Mentioned',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('No topics identified'),
            ],
          ),
        ),
      );
    }

    final maxCount = analysis.topics
        .map((t) => t.count)
        .reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Topics Mentioned',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: analysis.topics.length * 50.0,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxCount.toDouble() * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < analysis.topics.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                analysis.topics[index].category,
                                style: const TextStyle(fontSize: 10),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: analysis.topics.asMap().entries.map((entry) {
                    final index = entry.key;
                    final topic = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: topic.count.toDouble(),
                          color: Colors.indigo,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Agent Performance Radar Chart
  Widget _buildAgentPerformanceRadar(CallAnalysis analysis) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agent Performance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: RadarChart(
                RadarChartData(
                  dataSets: [
                    RadarDataSet(
                      fillColor: Colors.indigo.withValues(alpha: 0.3),
                      borderColor: Colors.indigo,
                      borderWidth: 2,
                      dataEntries: [
                        RadarEntry(value: analysis.agentPerformance.greeting),
                        RadarEntry(
                          value: analysis.agentPerformance.problemSolving,
                        ),
                        RadarEntry(value: analysis.agentPerformance.closing),
                      ],
                    ),
                  ],
                  radarBackgroundColor: Colors.grey.shade100,
                  borderData: FlBorderData(show: true),
                  radarBorderData: const BorderSide(
                    color: Colors.grey,
                    width: 1,
                  ),
                  titlePositionPercentageOffset: 0.2,
                  getTitle: (index, angle) {
                    switch (index) {
                      case 0:
                        return RadarChartTitle(text: 'Greeting', angle: angle);
                      case 1:
                        return RadarChartTitle(
                          text: 'Problem\nSolving',
                          angle: angle,
                        );
                      case 2:
                        return RadarChartTitle(text: 'Closing', angle: angle);
                      default:
                        return RadarChartTitle(text: '', angle: angle);
                    }
                  },
                  titleTextStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  tickCount: 5,
                  ticksTextStyle: const TextStyle(fontSize: 10),
                  tickBorderData: const BorderSide(color: Colors.grey),
                  gridBorderData: const BorderSide(
                    color: Colors.grey,
                    width: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Loudness Heat Map
  Widget _buildLoudnessHeatMap(CallAnalysis analysis) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Loudness & Sentiment Heat Map',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: Row(
                children: analysis.loudnessTrend.asMap().entries.map((entry) {
                  final point = entry.value;
                  final color = _getLoudnessColor(point.loudness);
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Word Cloud (simplified visual representation)
  Widget _buildWordCloud(CallAnalysis analysis) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Word Cloud',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: analysis.wordCloud.take(30).map((word) {
                final fontSize = 10.0 + (word.weight * 8.0);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    word.word,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Aggregate Charts
  Widget _buildTotalCallsChart(List<CallRecording> recordings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Total Calls',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              recordings.length.toString(),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsByLanguageChart(List<CallRecording> recordings) {
    final languageMap = <String, int>{};
    for (final recording in recordings) {
      final lang =
          recording.language ??
          recording.analysis?.detectedLanguage ??
          'Unknown';
      languageMap[lang] = (languageMap[lang] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calls by Language',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: languageMap.entries.map((entry) {
                    final percentage = (entry.value / recordings.length) * 100;
                    return PieChartSectionData(
                      value: percentage,
                      title: '${entry.key}\n${entry.value}',
                      color: _getColorForIndex(
                        languageMap.keys.toList().indexOf(entry.key),
                      ),
                      radius: 60,
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsByDepartmentChart(List<CallRecording> recordings) {
    final deptMap = <String, int>{};
    for (final recording in recordings) {
      final dept = recording.department ?? 'Unknown';
      deptMap[dept] = (deptMap[dept] ?? 0) + 1;
    }

    if (deptMap.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Calls by Department',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('No department data'),
            ],
          ),
        ),
      );
    }

    final maxCount = deptMap.values.reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calls by Department',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: deptMap.length * 40.0,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxCount.toDouble() * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          final depts = deptMap.keys.toList();
                          if (index >= 0 && index < depts.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                depts[index],
                                style: const TextStyle(fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: deptMap.entries.toList().asMap().entries.map((
                    entry,
                  ) {
                    final index = entry.key;
                    final dept = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: dept.value.toDouble(),
                          color: Colors.indigo,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsByWeekChart(List<CallRecording> recordings) {
    final weekMap = <String, int>{};
    for (final recording in recordings) {
      final week = _getWeekKey(recording.createdAt);
      weekMap[week] = (weekMap[week] ?? 0) + 1;
    }

    final sortedWeeks = weekMap.keys.toList()..sort();
    final maxCount = weekMap.values.reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calls by Week',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxCount.toDouble() * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < sortedWeeks.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                sortedWeeks[index],
                                style: const TextStyle(fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: sortedWeeks.asMap().entries.map((entry) {
                    final index = entry.key;
                    final week = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: weekMap[week]!.toDouble(),
                          color: Colors.indigo,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationDistributionChart(List<CallRecording> recordings) {
    final buckets = <String, int>{
      '< 30s': 0,
      '30-50s': 0,
      '50-90s': 0,
      '90-120s': 0,
      '> 120s': 0,
    };

    for (final recording in recordings) {
      final seconds = recording.duration.inSeconds;
      if (seconds < 30) {
        buckets['< 30s'] = buckets['< 30s']! + 1;
      } else if (seconds < 50) {
        buckets['30-50s'] = buckets['30-50s']! + 1;
      } else if (seconds < 90) {
        buckets['50-90s'] = buckets['50-90s']! + 1;
      } else if (seconds < 120) {
        buckets['90-120s'] = buckets['90-120s']! + 1;
      } else {
        buckets['> 120s'] = buckets['> 120s']! + 1;
      }
    }

    final maxCount = buckets.values.reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Duration Distribution',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxCount.toDouble() * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          final keys = buckets.keys.toList();
                          if (index >= 0 && index < keys.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                keys[index],
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: buckets.entries.toList().asMap().entries.map((
                    entry,
                  ) {
                    final index = entry.key;
                    final bucket = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: bucket.value.toDouble(),
                          color: Colors.indigo,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTalkTimeSentimentImpact(List<CallRecording> recordings) {
    final data = <String, List<double>>{
      'Agent Talks More': [],
      'Customer Talks More': [],
      'Balanced': [],
    };

    for (final recording in recordings) {
      final analysis = recording.analysis;
      if (analysis == null) continue;

      final sentiment = analysis.sentimentScore.score;
      final agentPct = analysis.talkTimeRatio.agentPercentage;
      final customerPct = analysis.talkTimeRatio.customerPercentage;

      if (agentPct > customerPct + 10) {
        data['Agent Talks More']!.add(sentiment);
      } else if (customerPct > agentPct + 10) {
        data['Customer Talks More']!.add(sentiment);
      } else {
        data['Balanced']!.add(sentiment);
      }
    }

    final avgSentiments = data.map(
      (key, values) => MapEntry(
        key,
        values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length,
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Talk Time Impact on Customer Sentiment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 1.0,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          final keys = avgSentiments.keys.toList();
                          if (index >= 0 && index < keys.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                keys[index],
                                style: const TextStyle(fontSize: 10),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: avgSentiments.entries.toList().asMap().entries.map(
                    (entry) {
                      final index = entry.key;
                      final sentiment = entry.value.value;
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: sentiment,
                            color: _getSentimentBarColor(sentiment),
                            width: 20,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      );
                    },
                  ).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentPerformanceComparison(List<CallRecording> recordings) {
    final agentMap = <String, List<double>>{};
    for (final recording in recordings) {
      final agent = recording.agentName ?? 'Unknown';
      final analysis = recording.analysis;
      if (analysis == null) continue;

      final avgPerformance =
          (analysis.agentPerformance.greeting +
              analysis.agentPerformance.problemSolving +
              analysis.agentPerformance.closing) /
          3.0;

      if (!agentMap.containsKey(agent)) {
        agentMap[agent] = [];
      }
      agentMap[agent]!.add(avgPerformance);
    }

    final avgPerformances = agentMap.map(
      (key, values) =>
          MapEntry(key, values.reduce((a, b) => a + b) / values.length),
    );

    if (avgPerformances.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Agent Performance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('No agent data available'),
            ],
          ),
        ),
      );
    }

    final sortedAgents = avgPerformances.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agent Performance Comparison',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: sortedAgents.length * 40.0,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 10.0,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < sortedAgents.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                sortedAgents[index].key,
                                style: const TextStyle(fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  barGroups: sortedAgents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final performance = entry.value.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: performance,
                          color: _getScoreColor(performance),
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsStatusChart(List<CallRecording> recordings) {
    final statusMap = <String, int>{};
    for (final recording in recordings) {
      final status = recording.status ?? 'Unknown';
      statusMap[status] = (statusMap[status] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calls Status Distribution',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: statusMap.entries.map((entry) {
                    final percentage = (entry.value / recordings.length) * 100;
                    return PieChartSectionData(
                      value: percentage,
                      title: '${entry.key}\n${entry.value}',
                      color: _getStatusColor(entry.key),
                      radius: 60,
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirstCallResolutionChart(List<CallRecording> recordings) {
    final resolved = recordings
        .where((r) => r.firstCallResolution == true)
        .length;
    final notResolved = recordings.length - resolved;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'First Call Resolution',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: resolved.toDouble(),
                      title: 'Resolved\n$resolved',
                      color: Colors.green,
                      radius: 60,
                    ),
                    PieChartSectionData(
                      value: notResolved.toDouble(),
                      title: 'Not Resolved\n$notResolved',
                      color: Colors.orange,
                      radius: 60,
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper Methods
  AggregateMetrics _calculateAggregateMetrics(List<CallRecording> recordings) {
    double totalAgentTalk = 0;
    double totalCustomerTalk = 0;
    int callsWithAgentTalk = 0;
    int callsWithCustomerTalk = 0;
    int firstCallResolutions = 0;
    int totalCalls = recordings.length;

    for (final recording in recordings) {
      final analysis = recording.analysis;
      if (analysis != null) {
        if (analysis.agentTalkSeconds > 0) {
          totalAgentTalk += analysis.agentTalkSeconds;
          callsWithAgentTalk++;
        }
        if (analysis.customerTalkSeconds > 0) {
          totalCustomerTalk += analysis.customerTalkSeconds;
          callsWithCustomerTalk++;
        }
        if (analysis.firstCallResolution == true ||
            recording.firstCallResolution == true) {
          firstCallResolutions++;
        }
      }
    }

    return AggregateMetrics(
      totalCalls: totalCalls,
      avgAgentTalkSec: callsWithAgentTalk > 0
          ? totalAgentTalk / callsWithAgentTalk
          : 0.0,
      avgCustomerTalkSec: callsWithCustomerTalk > 0
          ? totalCustomerTalk / callsWithCustomerTalk
          : 0.0,
      callsOver50Sec: recordings.where((r) => r.duration.inSeconds > 50).length,
      callsUnder50Sec: recordings
          .where((r) => r.duration.inSeconds <= 50)
          .length,
      firstCallResolutionRate: totalCalls > 0
          ? firstCallResolutions / totalCalls
          : 0.0,
    );
  }

  String _getWeekKey(DateTime date) {
    final weekStart = date.subtract(Duration(days: date.weekday - 1));
    return DateFormat('MMM dd').format(weekStart);
  }

  Color _getSentimentColor(String sentiment) {
    switch (sentiment.toLowerCase()) {
      case 'positive':
        return Colors.green;
      case 'negative':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 8) return Colors.green;
    if (score >= 6) return Colors.orange;
    return Colors.red;
  }

  Color _getLoudnessColor(double loudness) {
    if (loudness > 0.7) return Colors.red;
    if (loudness > 0.4) return Colors.orange;
    return Colors.green;
  }

  Color _getSentimentBarColor(double sentiment) {
    if (sentiment > 0.6) return Colors.green;
    if (sentiment > 0.3) return Colors.orange;
    return Colors.red;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'escalated':
        return Colors.red;
      case 'closed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
    ];
    return colors[index % colors.length];
  }
}

class AggregateMetrics {
  final int totalCalls;
  final double avgAgentTalkSec;
  final double avgCustomerTalkSec;
  final int callsOver50Sec;
  final int callsUnder50Sec;
  final double firstCallResolutionRate;

  AggregateMetrics({
    required this.totalCalls,
    required this.avgAgentTalkSec,
    required this.avgCustomerTalkSec,
    required this.callsOver50Sec,
    required this.callsUnder50Sec,
    required this.firstCallResolutionRate,
  });
}
