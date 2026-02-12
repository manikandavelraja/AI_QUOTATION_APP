import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/call_recording.dart';
import 'AI_Disclaimer.dart';

class CallInsightsDashboard extends StatelessWidget {
  final CallAnalysis analysis;

  const CallInsightsDashboard({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key Metrics Cards
          _buildKeyMetricsCards(),
          const SizedBox(height: 24),

          // Sentiment Trend Line Chart
          _buildSentimentTrendChart(),
          const SizedBox(height: 24),

          // Topics Bar Chart
          _buildTopicsBarChart(),
          const SizedBox(height: 24),

          // Agent Performance Radar Chart
          _buildAgentPerformanceRadar(),
          const SizedBox(height: 24),

          // Agent Score Details
          _buildAgentScoreDetails(),
          const SizedBox(height: 24),

          // Talk Time Details
          // _buildTalkTimeDetails(),
          // const SizedBox(height: 24),

          // AI Disclaimer
          const AIDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildKeyMetricsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            'Overall Sentiment',
            analysis.sentimentScore.overall,
            _getSentimentColor(analysis.sentimentScore.overall),
            Icons.sentiment_satisfied,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Sentiment Score',
            '${(analysis.sentimentScore.score * 100).toStringAsFixed(0)}%',
            _getSentimentColor(analysis.sentimentScore.overall),
            Icons.trending_up,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Agent Rating',
            '${analysis.agentScore.rating}/10',
            _getScoreColor(analysis.agentScore.rating.toDouble()),
            Icons.star,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentScoreDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agent Score Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Rating',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${analysis.agentScore.rating}/10',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(
                            analysis.agentScore.rating.toDouble(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Professionalism',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        analysis.agentScore.professionalism,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Efficiency',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        analysis.agentScore.efficiency,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget _buildTalkTimeDetails() {
  //   final totalTime = analysis.agentTalkSeconds + analysis.customerTalkSeconds;
  //   final agentPercentage = totalTime > 0
  //       ? (analysis.agentTalkSeconds / totalTime * 100).toStringAsFixed(1)
  //       : '0.0';
  //   final customerPercentage = totalTime > 0
  //       ? (analysis.customerTalkSeconds / totalTime * 100).toStringAsFixed(1)
  //       : '0.0';

  //   return Card(
  //     child: Padding(
  //       padding: const EdgeInsets.all(16),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           const Text(
  //             'Talk Time Analysis',
  //             style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  //           ),
  //           const SizedBox(height: 16),
  //           Row(
  //             children: [
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Row(
  //                       children: [
  //                         Icon(Icons.mic, color: Colors.blue, size: 20),
  //                         const SizedBox(width: 8),
  //                         const Text(
  //                           'Agent Talk Time',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 8),
  //                     Text(
  //                       '${analysis.agentTalkSeconds.toStringAsFixed(0)}s',
  //                       style: const TextStyle(
  //                         fontSize: 20,
  //                         fontWeight: FontWeight.bold,
  //                         color: Colors.blue,
  //                       ),
  //                     ),
  //                     Text(
  //                       '$agentPercentage% of total',
  //                       style: TextStyle(
  //                         fontSize: 12,
  //                         color: Colors.grey.shade600,
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Row(
  //                       children: [
  //                         Icon(Icons.person, color: Colors.green, size: 20),
  //                         const SizedBox(width: 8),
  //                         const Text(
  //                           'Customer Talk Time',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 8),
  //                     Text(
  //                       '${analysis.customerTalkSeconds.toStringAsFixed(0)}s',
  //                       style: const TextStyle(
  //                         fontSize: 20,
  //                         fontWeight: FontWeight.bold,
  //                         color: Colors.green,
  //                       ),
  //                     ),
  //                     Text(
  //                       '$customerPercentage% of total',
  //                       style: TextStyle(
  //                         fontSize: 12,
  //                         color: Colors.grey.shade600,
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Row(
  //                       children: [
  //                         Icon(Icons.timer, color: Colors.purple, size: 20),
  //                         const SizedBox(width: 8),
  //                         const Text(
  //                           'Total Duration',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 8),
  //                     Text(
  //                       '${totalTime.toStringAsFixed(0)}s',
  //                       style: const TextStyle(
  //                         fontSize: 20,
  //                         fontWeight: FontWeight.bold,
  //                         color: Colors.purple,
  //                       ),
  //                     ),
  //                     Text(
  //                       'Call length',
  //                       style: TextStyle(
  //                         fontSize: 12,
  //                         color: Colors.grey.shade600,
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

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

  Widget _buildSentimentTrendChart() {
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
        : (sentimentValues.reduce((a, b) => a < b ? a : b) - 0.2).clamp(-1.0, 1.0);
    final maxY = sentimentValues.isEmpty 
        ? 1.0 
        : (sentimentValues.reduce((a, b) => a > b ? a : b) + 0.2).clamp(-1.0, 1.0);
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        color: Colors.indigo.withOpacity(0.1),
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

  Widget _buildTopicsBarChart() {
    if (analysis.topics.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Topics Mentioned',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Widget _buildAgentPerformanceRadar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agent Performance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: RadarChart(
                RadarChartData(
                  dataSets: [
                    RadarDataSet(
                      fillColor: Colors.indigo.withOpacity(0.3),
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
            const SizedBox(height: 16),
            // Performance details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPerformanceMetric(
                  'Greeting',
                  analysis.agentPerformance.greeting,
                ),
                _buildPerformanceMetric(
                  'Problem Solving',
                  analysis.agentPerformance.problemSolving,
                ),
                _buildPerformanceMetric(
                  'Closing',
                  analysis.agentPerformance.closing,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceMetric(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _getScoreColor(value),
          ),
        ),
      ],
    );
  }
}
