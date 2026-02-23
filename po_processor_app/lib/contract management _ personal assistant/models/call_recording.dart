class CallRecording {
  final String id;
  final String fileName;
  final String filePath;
  final Duration duration;
  final DateTime createdAt;
  final String? transcript;
  final CallAnalysis? analysis;
  // Call metadata
  final String? language;
  final String? department;
  final String? agentName;
  final String? status; // 'Resolved', 'Pending', 'Escalated', 'Closed'
  final bool? firstCallResolution;
  final double? loudness; // Average loudness level
  final Map<String, dynamic>? metadata; // Additional metadata

  CallRecording({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.duration,
    required this.createdAt,
    this.transcript,
    this.analysis,
    this.language,
    this.department,
    this.agentName,
    this.status,
    this.firstCallResolution,
    this.loudness,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'filePath': filePath,
      'duration': duration.inSeconds,
      'createdAt': createdAt.toIso8601String(),
      'transcript': transcript,
      'analysis': analysis?.toJson(),
      'language': language,
      'department': department,
      'agentName': agentName,
      'status': status,
      'firstCallResolution': firstCallResolution,
      'loudness': loudness,
      'metadata': metadata,
    };
  }

  factory CallRecording.fromJson(Map<String, dynamic> json) {
    return CallRecording(
      id: json['id'],
      fileName: json['fileName'],
      filePath: json['filePath'],
      duration: Duration(seconds: json['duration'] ?? 0),
      createdAt: DateTime.parse(json['createdAt']),
      transcript: json['transcript'],
      analysis: json['analysis'] != null
          ? CallAnalysis.fromJson(json['analysis'])
          : null,
      language: json['language'],
      department: json['department'],
      agentName: json['agentName'],
      status: json['status'],
      firstCallResolution: json['firstCallResolution'],
      loudness: json['loudness'] != null ? (json['loudness'] as num).toDouble() : null,
      metadata: json['metadata'] != null ? Map<String, dynamic>.from(json['metadata']) : null,
    );
  }
}

class TranscriptMessage {
  final String speaker; // 'agent' or 'customer'
  final String text;
  final DateTime timestamp;
  final Duration? duration;
  final double? sentiment; // Sentiment for this message (-1.0 to 1.0)
  final double? loudness; // Loudness level for this segment

  TranscriptMessage({
    required this.speaker,
    required this.text,
    required this.timestamp,
    this.duration,
    this.sentiment,
    this.loudness,
  });

  Map<String, dynamic> toJson() {
    return {
      'speaker': speaker,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration?.inSeconds,
      'sentiment': sentiment,
      'loudness': loudness,
    };
  }

  factory TranscriptMessage.fromJson(Map<String, dynamic> json) {
    return TranscriptMessage(
      speaker: json['speaker'],
      text: json['text'],
      timestamp: DateTime.parse(json['timestamp']),
      duration: json['duration'] != null
          ? Duration(seconds: json['duration'])
          : null,
      sentiment: json['sentiment'] != null ? (json['sentiment'] as num).toDouble() : null,
      loudness: json['loudness'] != null ? (json['loudness'] as num).toDouble() : null,
    );
  }
}

class CallAnalysis {
  final SentimentScore sentimentScore;
  final KeyHighlights keyHighlights;
  final AgentScore agentScore;
  final SentimentTrend sentimentTrend;
  final TalkTimeRatio talkTimeRatio;
  final List<TopicMention> topics;
  final AgentPerformance agentPerformance;
  // Additional metrics
  final double agentTalkSeconds;
  final double customerTalkSeconds;
  final String? detectedLanguage;
  final String? agentSentiment; // 'Positive', 'Neutral', 'Negative'
  final List<WordFrequency> wordCloud; // Top words for word cloud
  final List<LoudnessDataPoint> loudnessTrend; // Loudness over time
  final bool? firstCallResolution;

  CallAnalysis({
    required this.sentimentScore,
    required this.keyHighlights,
    required this.agentScore,
    required this.sentimentTrend,
    required this.talkTimeRatio,
    required this.topics,
    required this.agentPerformance,
    this.agentTalkSeconds = 0.0,
    this.customerTalkSeconds = 0.0,
    this.detectedLanguage,
    this.agentSentiment,
    this.wordCloud = const [],
    this.loudnessTrend = const [],
    this.firstCallResolution,
  });

  Map<String, dynamic> toJson() {
    return {
      'sentimentScore': sentimentScore.toJson(),
      'keyHighlights': keyHighlights.toJson(),
      'agentScore': agentScore.toJson(),
      'sentimentTrend': sentimentTrend.toJson(),
      'talkTimeRatio': talkTimeRatio.toJson(),
      'topics': topics.map((t) => t.toJson()).toList(),
      'agentPerformance': agentPerformance.toJson(),
      'agentTalkSeconds': agentTalkSeconds,
      'customerTalkSeconds': customerTalkSeconds,
      'detectedLanguage': detectedLanguage,
      'agentSentiment': agentSentiment,
      'wordCloud': wordCloud.map((w) => w.toJson()).toList(),
      'loudnessTrend': loudnessTrend.map((l) => l.toJson()).toList(),
      'firstCallResolution': firstCallResolution,
    };
  }

  factory CallAnalysis.fromJson(Map<String, dynamic> json) {
    return CallAnalysis(
      sentimentScore: SentimentScore.fromJson(json['sentimentScore']),
      keyHighlights: KeyHighlights.fromJson(json['keyHighlights']),
      agentScore: AgentScore.fromJson(json['agentScore']),
      sentimentTrend: SentimentTrend.fromJson(json['sentimentTrend']),
      talkTimeRatio: TalkTimeRatio.fromJson(json['talkTimeRatio']),
      topics: (json['topics'] as List)
          .map((t) => TopicMention.fromJson(t))
          .toList(),
      agentPerformance:
          AgentPerformance.fromJson(json['agentPerformance']),
      agentTalkSeconds: (json['agentTalkSeconds'] as num?)?.toDouble() ?? 0.0,
      customerTalkSeconds: (json['customerTalkSeconds'] as num?)?.toDouble() ?? 0.0,
      detectedLanguage: json['detectedLanguage'],
      agentSentiment: json['agentSentiment'],
      wordCloud: json['wordCloud'] != null
          ? (json['wordCloud'] as List)
              .map((w) => WordFrequency.fromJson(w))
              .toList()
          : [],
      loudnessTrend: json['loudnessTrend'] != null
          ? (json['loudnessTrend'] as List)
              .map((l) => LoudnessDataPoint.fromJson(l))
              .toList()
          : [],
      firstCallResolution: json['firstCallResolution'],
    );
  }
}

class SentimentScore {
  final String overall; // 'Positive', 'Neutral', 'Negative'
  final double score; // 0.0 to 1.0

  SentimentScore({
    required this.overall,
    required this.score,
  });

  Map<String, dynamic> toJson() {
    return {
      'overall': overall,
      'score': score,
    };
  }

  factory SentimentScore.fromJson(Map<String, dynamic> json) {
    return SentimentScore(
      overall: json['overall'],
      score: (json['score'] as num).toDouble(),
    );
  }
}

class KeyHighlights {
  final String issue;
  final String resolution;
  final String summary;

  KeyHighlights({
    required this.issue,
    required this.resolution,
    required this.summary,
  });

  Map<String, dynamic> toJson() {
    return {
      'issue': issue,
      'resolution': resolution,
      'summary': summary,
    };
  }

  factory KeyHighlights.fromJson(Map<String, dynamic> json) {
    return KeyHighlights(
      issue: json['issue']?.toString().trim() ?? 'Issue identified in call',
      resolution: json['resolution']?.toString().trim() ?? 'Resolution discussed',
      summary: json['summary']?.toString().trim() ?? 'Call summary',
    );
  }
}

class AgentScore {
  final int rating; // 1-10
  final String professionalism;
  final String efficiency;

  AgentScore({
    required this.rating,
    required this.professionalism,
    required this.efficiency,
  });

  Map<String, dynamic> toJson() {
    return {
      'rating': rating,
      'professionalism': professionalism,
      'efficiency': efficiency,
    };
  }

  factory AgentScore.fromJson(Map<String, dynamic> json) {
    return AgentScore(
      rating: json['rating'],
      professionalism: json['professionalism'],
      efficiency: json['efficiency'],
    );
  }
}

class SentimentTrend {
  final List<SentimentDataPoint> dataPoints;

  SentimentTrend({required this.dataPoints});

  Map<String, dynamic> toJson() {
    return {
      'dataPoints': dataPoints.map((d) => d.toJson()).toList(),
    };
  }

  factory SentimentTrend.fromJson(Map<String, dynamic> json) {
    return SentimentTrend(
      dataPoints: (json['dataPoints'] as List)
          .map((d) => SentimentDataPoint.fromJson(d))
          .toList(),
    );
  }
}

class SentimentDataPoint {
  final double timestamp; // Time in seconds from start
  final double sentiment; // -1.0 (negative) to 1.0 (positive)

  SentimentDataPoint({
    required this.timestamp,
    required this.sentiment,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'sentiment': sentiment,
    };
  }

  factory SentimentDataPoint.fromJson(Map<String, dynamic> json) {
    return SentimentDataPoint(
      timestamp: (json['timestamp'] as num).toDouble(),
      sentiment: (json['sentiment'] as num).toDouble(),
    );
  }
}

class TalkTimeRatio {
  final double agentPercentage;
  final double customerPercentage;

  TalkTimeRatio({
    required this.agentPercentage,
    required this.customerPercentage,
  });

  Map<String, dynamic> toJson() {
    return {
      'agentPercentage': agentPercentage,
      'customerPercentage': customerPercentage,
    };
  }

  factory TalkTimeRatio.fromJson(Map<String, dynamic> json) {
    return TalkTimeRatio(
      agentPercentage: (json['agentPercentage'] as num).toDouble(),
      customerPercentage: (json['customerPercentage'] as num).toDouble(),
    );
  }
}

class TopicMention {
  final String category;
  final int count;
  final double percentage;

  TopicMention({
    required this.category,
    required this.count,
    required this.percentage,
  });

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'count': count,
      'percentage': percentage,
    };
  }

  factory TopicMention.fromJson(Map<String, dynamic> json) {
    return TopicMention(
      category: json['category'],
      count: json['count'],
      percentage: (json['percentage'] as num).toDouble(),
    );
  }
}

class AgentPerformance {
  final double greeting; // 0-10
  final double problemSolving; // 0-10
  final double closing; // 0-10

  AgentPerformance({
    required this.greeting,
    required this.problemSolving,
    required this.closing,
  });

  Map<String, dynamic> toJson() {
    return {
      'greeting': greeting,
      'problemSolving': problemSolving,
      'closing': closing,
    };
  }

  factory AgentPerformance.fromJson(Map<String, dynamic> json) {
    return AgentPerformance(
      greeting: (json['greeting'] as num).toDouble(),
      problemSolving: (json['problemSolving'] as num).toDouble(),
      closing: (json['closing'] as num).toDouble(),
    );
  }
}

class WordFrequency {
  final String word;
  final int frequency;
  final double weight; // For word cloud sizing

  WordFrequency({
    required this.word,
    required this.frequency,
    this.weight = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'frequency': frequency,
      'weight': weight,
    };
  }

  factory WordFrequency.fromJson(Map<String, dynamic> json) {
    return WordFrequency(
      word: json['word'],
      frequency: json['frequency'],
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class LoudnessDataPoint {
  final double timestamp; // Time in seconds from start
  final double loudness; // Loudness level (0.0 to 1.0)

  LoudnessDataPoint({
    required this.timestamp,
    required this.loudness,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'loudness': loudness,
    };
  }

  factory LoudnessDataPoint.fromJson(Map<String, dynamic> json) {
    return LoudnessDataPoint(
      timestamp: (json['timestamp'] as num).toDouble(),
      loudness: (json['loudness'] as num).toDouble(),
    );
  }
}

