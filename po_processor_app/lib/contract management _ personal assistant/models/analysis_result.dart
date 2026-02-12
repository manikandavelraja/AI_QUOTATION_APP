class AnalysisResult {
  final String summary;
  final String detailedContent;
  final double confidenceScore;
  final String imagePath;
  final DateTime timestamp;

  AnalysisResult({
    required this.summary,
    required this.detailedContent,
    required this.confidenceScore,
    required this.imagePath,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'summary': summary,
      'detailedContent': detailedContent,
      'confidenceScore': confidenceScore,
      'imagePath': imagePath,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      summary: json['summary'] ?? '',
      detailedContent: json['detailedContent'] ?? '',
      confidenceScore: (json['confidenceScore'] ?? 0.0).toDouble(),
      imagePath: json['imagePath'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

