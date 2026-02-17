import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../models/call_recording.dart';
import '../utils/logger.dart';
import '../utils/config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' if (dart.library.html) '../io_stub.dart';

class CallAnalysisService {
  final Dio _dio = Dio();
  final String _apiKey = Config.geminiApiKey;
  final String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  CallAnalysisService() {
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(seconds: 180);
    _dio.options.sendTimeout = const Duration(seconds: 60);
  }

  /// Analyze call transcript and return structured analysis
  Future<CallAnalysis> analyzeCallTranscript(
    String transcript,
    List<TranscriptMessage> messages,
  ) async {
    try {
      AppLogger.info(
        'Analyzing call transcript with ${messages.length} messages',
      );

      // Calculate talk time ratio
      final talkTimeRatio = _calculateTalkTimeRatio(messages);

      // Prepare prompt for Gemini
      final prompt = _buildAnalysisPrompt(transcript, messages, talkTimeRatio);

      // Call Gemini API
      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.3,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 4096,
          },
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final content =
            response.data['candidates'][0]['content']['parts'][0]['text'];
        AppLogger.info('Received call analysis from Gemini API');
        return _parseAnalysisResponse(
          content,
          transcript,
          messages,
          talkTimeRatio,
        );
      } else {
        throw Exception('Failed to analyze call: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error in CallAnalysisService.analyzeCallTranscript', e);
      // Return default analysis on error
      return _createDefaultAnalysis(messages);
    }
  }

  String _buildAnalysisPrompt(
    String transcript,
    List<TranscriptMessage> messages,
    TalkTimeRatio talkTimeRatio,
  ) {
    return '''
Analyze the following customer service call transcript and provide a comprehensive analysis in JSON format.

TRANSCRIPT:
$transcript

MESSAGES BREAKDOWN:
${messages.map((m) => '${m.speaker.toUpperCase()}: ${m.text} [${m.timestamp}]').join('\n')}

TALK TIME:
Agent: ${talkTimeRatio.agentPercentage.toStringAsFixed(1)}%
Customer: ${talkTimeRatio.customerPercentage.toStringAsFixed(1)}%

Please provide a detailed analysis in the following JSON format:
{
  "sentimentScore": {
    "overall": "Positive|Neutral|Negative",
    "score": 0.0-1.0
  },
  "keyHighlights": {
    "issue": "Brief description of the main issue",
    "resolution": "How the issue was resolved",
    "summary": "Overall summary of the call"
  },
  "agentScore": {
    "rating": 1-10,
    "professionalism": "Brief assessment",
    "efficiency": "Brief assessment"
  },
  "sentimentTrend": {
    "dataPoints": [
      {"timestamp": 0.0, "sentiment": -1.0 to 1.0},
      {"timestamp": 30.0, "sentiment": -1.0 to 1.0},
      ...
    ]
  },
  "topics": [
    {"category": "Product Quality", "count": 5, "percentage": 25.0},
    {"category": "Delivery Time", "count": 3, "percentage": 15.0},
    {"category": "Price", "count": 2, "percentage": 10.0},
    ...
  ],
  "agentPerformance": {
    "greeting": 0-10,
    "problemSolving": 0-10,
    "closing": 0-10
  },
  "detectedLanguage": "English|Spanish|French|etc",
  "agentSentiment": "Positive|Neutral|Negative",
  "wordCloud": [
    {"word": "issue", "frequency": 10, "weight": 1.0},
    {"word": "problem", "frequency": 8, "weight": 0.8},
    ...
  ],
  "firstCallResolution": true|false
}

Generate sentiment trend data points at regular intervals throughout the call duration.
Identify all topics mentioned and categorize them (Product Quality, Delivery Time, Price, Billing, Technical Support, etc.).
Rate agent performance on greeting, problem solving, and closing skills.
Detect the language of the conversation.
Analyze agent's sentiment throughout the call.
Extract top 30 most frequent words (excluding common stop words) for word cloud visualization.
Determine if this was a first call resolution (issue resolved in single call).
''';
  }

  CallAnalysis _parseAnalysisResponse(
    String content,
    String transcript,
    List<TranscriptMessage> messages,
    TalkTimeRatio talkTimeRatio,
  ) {
    try {
      String jsonString = content;

      // Remove markdown code blocks if present
      if (jsonString.contains('```json')) {
        final startIndex = jsonString.indexOf('```json') + 7;
        final endIndex = jsonString.indexOf('```', startIndex);
        if (endIndex != -1) {
          jsonString = jsonString.substring(startIndex, endIndex).trim();
        }
      } else if (jsonString.contains('```')) {
        final startIndex = jsonString.indexOf('```') + 3;
        final endIndex = jsonString.indexOf('```', startIndex);
        if (endIndex != -1) {
          jsonString = jsonString.substring(startIndex, endIndex).trim();
        }
      }

      final jsonData = jsonDecode(jsonString);

      // Calculate talk time in seconds (must match what's displayed)
      final agentTalkSeconds = _calculateAgentTalkSeconds(messages);
      final customerTalkSeconds = _calculateCustomerTalkSeconds(messages);

      // Generate word cloud from transcript
      final wordCloud = _generateWordCloud(transcript);

      // Generate loudness trend (simulated based on message length and sentiment)
      final loudnessTrend = _generateLoudnessTrend(messages);

      // Parse sentiment trend - ensure it has data points
      SentimentTrend sentimentTrend;
      try {
        final trendData = jsonData['sentimentTrend'];
        if (trendData != null && trendData['dataPoints'] != null) {
          final dataPoints = (trendData['dataPoints'] as List)
              .map((d) => SentimentDataPoint.fromJson(d))
              .toList();
          // If no data points or empty, generate them
          if (dataPoints.isEmpty) {
            sentimentTrend = _generateSentimentTrend(
              messages,
              agentTalkSeconds + customerTalkSeconds,
            );
          } else {
            sentimentTrend = SentimentTrend(dataPoints: dataPoints);
          }
        } else {
          sentimentTrend = _generateSentimentTrend(
            messages,
            agentTalkSeconds + customerTalkSeconds,
          );
        }
      } catch (e) {
        AppLogger.warning('Error parsing sentiment trend, generating default');
        sentimentTrend = _generateSentimentTrend(
          messages,
          agentTalkSeconds + customerTalkSeconds,
        );
      }

      // Parse topics - ensure at least one topic exists
      List<TopicMention> topics;
      try {
        if (jsonData['topics'] != null && jsonData['topics'] is List) {
          topics = (jsonData['topics'] as List)
              .map((t) => TopicMention.fromJson(t))
              .toList();
          // Calculate percentages if not provided
          if (topics.isNotEmpty) {
            final totalCount = topics.fold<int>(
              0,
              (sum, topic) => sum + topic.count,
            );
            if (totalCount > 0) {
              topics = topics.map((topic) {
                return TopicMention(
                  category: topic.category,
                  count: topic.count,
                  percentage: (topic.count / totalCount) * 100,
                );
              }).toList();
            }
          }
        } else {
          topics = [];
        }
        // If no topics, generate default from transcript
        if (topics.isEmpty) {
          topics = _extractTopicsFromTranscript(transcript);
        }
      } catch (e) {
        AppLogger.warning('Error parsing topics, extracting from transcript');
        topics = _extractTopicsFromTranscript(transcript);
      }

      // Parse and validate keyHighlights
      KeyHighlights keyHighlights;
      try {
        final highlightsData = jsonData['keyHighlights'];
        if (highlightsData != null) {
          keyHighlights = KeyHighlights.fromJson(highlightsData);
          // Check if fields are empty or just default values
          final issueEmpty =
              keyHighlights.issue.isEmpty ||
              keyHighlights.issue == 'Issue identified in call';
          final resolutionEmpty =
              keyHighlights.resolution.isEmpty ||
              keyHighlights.resolution == 'Resolution discussed';
          final summaryEmpty =
              keyHighlights.summary.isEmpty ||
              keyHighlights.summary == 'Call summary';

          // Extract from transcript if any fields are empty or default
          if (issueEmpty || resolutionEmpty || summaryEmpty) {
            AppLogger.info(
              'Key highlights have empty/default values, extracting from transcript',
            );
            keyHighlights = _extractKeyHighlightsFromTranscript(
              transcript,
              highlightsData,
            );
          }
        } else {
          AppLogger.info(
            'No keyHighlights in JSON, extracting from transcript',
          );
          keyHighlights = _extractKeyHighlightsFromTranscript(transcript, null);
        }
      } catch (e) {
        AppLogger.warning(
          'Error parsing keyHighlights, extracting from transcript: $e',
        );
        keyHighlights = _extractKeyHighlightsFromTranscript(transcript, null);
      }

      // Parse and validate sentimentScore
      SentimentScore sentimentScore;
      try {
        sentimentScore = SentimentScore.fromJson(jsonData['sentimentScore']);
      } catch (e) {
        AppLogger.warning('Error parsing sentimentScore, using defaults');
        sentimentScore = SentimentScore(overall: 'Neutral', score: 0.5);
      }

      // Parse and validate agentScore
      AgentScore agentScore;
      try {
        agentScore = AgentScore.fromJson(jsonData['agentScore']);
      } catch (e) {
        AppLogger.warning('Error parsing agentScore, using defaults');
        agentScore = AgentScore(
          rating: 7,
          professionalism: 'Professional service provided',
          efficiency: 'Efficient problem resolution',
        );
      }

      // Parse and validate agentPerformance
      AgentPerformance agentPerformance;
      try {
        agentPerformance = AgentPerformance.fromJson(
          jsonData['agentPerformance'],
        );
      } catch (e) {
        AppLogger.warning('Error parsing agentPerformance, using defaults');
        agentPerformance = AgentPerformance(
          greeting: 7.0,
          problemSolving: 7.0,
          closing: 7.0,
        );
      }

      return CallAnalysis(
        sentimentScore: sentimentScore,
        keyHighlights: keyHighlights,
        agentScore: agentScore,
        sentimentTrend: sentimentTrend,
        talkTimeRatio: talkTimeRatio,
        topics: topics,
        agentPerformance: agentPerformance,
        agentTalkSeconds: agentTalkSeconds,
        customerTalkSeconds: customerTalkSeconds,
        detectedLanguage: jsonData['detectedLanguage'] ?? 'English',
        agentSentiment: jsonData['agentSentiment'] ?? 'Neutral',
        wordCloud: wordCloud,
        loudnessTrend: loudnessTrend,
        firstCallResolution: jsonData['firstCallResolution'] ?? false,
      );
    } catch (e) {
      AppLogger.error('Error parsing call analysis response as JSON', e);
      // Try to extract data from text response instead of returning defaults
      // Reconstruct transcript from messages for word cloud generation
      final reconstructedTranscript = messages.map((m) => m.text).join(' ');
      return _extractAnalysisFromText(
        content,
        reconstructedTranscript,
        messages,
        talkTimeRatio,
      );
    }
  }

  /// Extract analysis data from text response when JSON parsing fails
  CallAnalysis _extractAnalysisFromText(
    String content,
    String transcript,
    List<TranscriptMessage> messages,
    TalkTimeRatio talkTimeRatio,
  ) {
    try {
      AppLogger.info('Attempting to extract analysis from text response');

      // Extract sentiment
      String sentiment = 'Neutral';
      double sentimentScore = 0.5;
      final sentimentMatch = RegExp(
        r'(?:sentiment|overall)[\s:]+(Positive|Neutral|Negative)',
        caseSensitive: false,
      ).firstMatch(content);
      if (sentimentMatch != null) {
        sentiment = sentimentMatch.group(1) ?? 'Neutral';
      }

      // Extract sentiment score
      final scoreMatch = RegExp(r'score["\s:]+([0-9.]+)').firstMatch(content);
      if (scoreMatch != null) {
        sentimentScore = double.tryParse(scoreMatch.group(1) ?? '0.5') ?? 0.5;
      }

      // Extract key highlights - try from content first, then from transcript
      KeyHighlights keyHighlights;
      try {
        // Try to extract from content
        String issue = 'Issue identified in call';
        String resolution = 'Resolution discussed';
        String summary = 'Call summary';

        final issueMatch = RegExp(
          r'(?:issue|problem)[\s:]+(.+?)(?:\n|resolution|summary|$)',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(content);
        if (issueMatch != null) {
          issue = issueMatch.group(1)?.trim() ?? issue;
        }

        final resolutionMatch = RegExp(
          r'(?:resolution|solution)[\s:]+(.+?)(?:\n|summary|$)',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(content);
        if (resolutionMatch != null) {
          resolution = resolutionMatch.group(1)?.trim() ?? resolution;
        }

        final summaryMatch = RegExp(
          r'(?:summary|overall)[\s:]+(.+?)(?:\n\n|$)',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(content);
        if (summaryMatch != null) {
          summary = summaryMatch.group(1)?.trim() ?? summary;
        }

        // If extracted values are still default or empty, use helper method
        if (issue.isEmpty ||
            issue == 'Issue identified in call' ||
            resolution.isEmpty ||
            resolution == 'Resolution discussed' ||
            summary.isEmpty ||
            summary == 'Call summary') {
          keyHighlights = _extractKeyHighlightsFromTranscript(transcript, {
            'issue': issue,
            'resolution': resolution,
            'summary': summary,
          });
        } else {
          keyHighlights = KeyHighlights(
            issue: issue,
            resolution: resolution,
            summary: summary,
          );
        }
      } catch (e) {
        AppLogger.warning('Error extracting key highlights, using transcript');
        keyHighlights = _extractKeyHighlightsFromTranscript(transcript, null);
      }

      // Extract agent rating
      int rating = 7;
      final ratingMatch = RegExp(
        r'(?:rating|score)[\s:]+(\d+)',
      ).firstMatch(content);
      if (ratingMatch != null) {
        rating = int.tryParse(ratingMatch.group(1) ?? '7') ?? 7;
      }

      // Extract topics from content first, then from transcript if needed
      final topics = <TopicMention>[];
      final topicMatches = RegExp(
        r'(?:topic|category)[\s:]+(\w+)[\s:]+(\d+)',
      ).allMatches(content);
      for (final match in topicMatches) {
        topics.add(
          TopicMention(
            category: match.group(1) ?? 'Other',
            count: int.tryParse(match.group(2) ?? '1') ?? 1,
            percentage: 0.0,
          ),
        );
      }

      // If no topics found, extract from transcript
      if (topics.isEmpty) {
        topics.addAll(_extractTopicsFromTranscript(transcript));
      } else {
        // Calculate percentages
        final totalCount = topics.fold<int>(
          0,
          (sum, topic) => sum + topic.count,
        );
        if (totalCount > 0) {
          for (int i = 0; i < topics.length; i++) {
            topics[i] = TopicMention(
              category: topics[i].category,
              count: topics[i].count,
              percentage: (topics[i].count / totalCount) * 100,
            );
          }
        }
      }

      // Calculate total duration from actual message durations
      final totalDuration =
          _calculateAgentTalkSeconds(messages) +
          _calculateCustomerTalkSeconds(messages);

      // Generate sentiment trend from messages using helper method
      final sentimentTrend = _generateSentimentTrend(messages, totalDuration);

      // Extract agent performance scores
      double greeting = 7.0;
      double problemSolving = 7.0;
      double closing = 7.0;

      final greetingMatch = RegExp(
        r'greeting[\s:]+(\d+\.?\d*)',
      ).firstMatch(content);
      if (greetingMatch != null) {
        greeting = double.tryParse(greetingMatch.group(1) ?? '7.0') ?? 7.0;
      }

      final problemMatch = RegExp(
        r'problem[\s-]?solving[\s:]+(\d+\.?\d*)',
      ).firstMatch(content);
      if (problemMatch != null) {
        problemSolving = double.tryParse(problemMatch.group(1) ?? '7.0') ?? 7.0;
      }

      final closingMatch = RegExp(
        r'closing[\s:]+(\d+\.?\d*)',
      ).firstMatch(content);
      if (closingMatch != null) {
        closing = double.tryParse(closingMatch.group(1) ?? '7.0') ?? 7.0;
      }

      // Calculate talk time in seconds
      final agentTalkSeconds = _calculateAgentTalkSeconds(messages);
      final customerTalkSeconds = _calculateCustomerTalkSeconds(messages);

      // Generate word cloud from transcript
      final wordCloud = _generateWordCloud(transcript);

      // Generate loudness trend
      final loudnessTrend = _generateLoudnessTrend(messages);

      return CallAnalysis(
        sentimentScore: SentimentScore(
          overall: sentiment,
          score: sentimentScore,
        ),
        keyHighlights: keyHighlights,
        agentScore: AgentScore(
          rating: rating,
          professionalism: 'Professional service provided',
          efficiency: 'Efficient problem resolution',
        ),
        sentimentTrend: sentimentTrend,
        talkTimeRatio: talkTimeRatio,
        topics: topics.isEmpty
            ? [
                TopicMention(
                  category: 'Customer Service',
                  count: 1,
                  percentage: 100.0,
                ),
              ]
            : topics,
        agentPerformance: AgentPerformance(
          greeting: greeting,
          problemSolving: problemSolving,
          closing: closing,
        ),
        agentTalkSeconds: agentTalkSeconds,
        customerTalkSeconds: customerTalkSeconds,
        detectedLanguage: 'English',
        agentSentiment: 'Neutral',
        wordCloud: wordCloud,
        loudnessTrend: loudnessTrend,
        firstCallResolution:
            keyHighlights.resolution.toLowerCase().contains('resolved') ||
            keyHighlights.resolution.toLowerCase().contains('fixed') ||
            keyHighlights.resolution.toLowerCase().contains('solved'),
      );
    } catch (e) {
      AppLogger.error('Error extracting analysis from text', e);
      // Only return defaults as last resort
      return _createDefaultAnalysis(messages);
    }
  }

  CallAnalysis _createDefaultAnalysis(List<TranscriptMessage> messages) {
    final talkTimeRatio = _calculateTalkTimeRatio(messages);
    final agentTalkSeconds = _calculateAgentTalkSeconds(messages);
    final customerTalkSeconds = _calculateCustomerTalkSeconds(messages);
    final totalDuration = agentTalkSeconds + customerTalkSeconds;

    // Reconstruct transcript for topic extraction
    final transcript = messages.map((m) => m.text).join(' ');

    AppLogger.warning(
      'Using default analysis - API response could not be parsed',
    );
    return CallAnalysis(
      sentimentScore: SentimentScore(overall: 'Neutral', score: 0.5),
      keyHighlights: KeyHighlights(
        issue: 'Analysis unavailable',
        resolution: 'Unable to extract resolution',
        summary: 'Call analysis could not be completed. Please try again.',
      ),
      agentScore: AgentScore(
        rating: 5,
        professionalism: 'Unable to assess',
        efficiency: 'Unable to assess',
      ),
      sentimentTrend: _generateSentimentTrend(messages, totalDuration),
      talkTimeRatio: talkTimeRatio,
      topics: _extractTopicsFromTranscript(transcript),
      agentPerformance: AgentPerformance(
        greeting: 5.0,
        problemSolving: 5.0,
        closing: 5.0,
      ),
      agentTalkSeconds: agentTalkSeconds,
      customerTalkSeconds: customerTalkSeconds,
      detectedLanguage: 'English',
      agentSentiment: 'Neutral',
      wordCloud: _generateWordCloud(transcript),
      loudnessTrend: _generateLoudnessTrend(messages),
      firstCallResolution: null,
    );
  }

  TalkTimeRatio _calculateTalkTimeRatio(List<TranscriptMessage> messages) {
    // Use the same calculation as agent/customer talk seconds for consistency
    final agentTime = _calculateAgentTalkSeconds(messages);
    final customerTime = _calculateCustomerTalkSeconds(messages);
    final total = agentTime + customerTime;

    if (total == 0) {
      return TalkTimeRatio(agentPercentage: 50.0, customerPercentage: 50.0);
    }

    return TalkTimeRatio(
      agentPercentage: (agentTime / total) * 100,
      customerPercentage: (customerTime / total) * 100,
    );
  }

  double _calculateAgentTalkSeconds(List<TranscriptMessage> messages) {
    double total = 0;
    for (final message in messages) {
      if (message.speaker.toLowerCase() == 'agent') {
        total += message.duration?.inSeconds.toDouble() ?? 5.0;
      }
    }
    return total;
  }

  double _calculateCustomerTalkSeconds(List<TranscriptMessage> messages) {
    double total = 0;
    for (final message in messages) {
      if (message.speaker.toLowerCase() != 'agent') {
        total += message.duration?.inSeconds.toDouble() ?? 5.0;
      }
    }
    return total;
  }

  List<WordFrequency> _generateWordCloud(String transcript) {
    // Remove common stop words
    final stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'by',
      'from',
      'as',
      'is',
      'was',
      'are',
      'were',
      'been',
      'be',
      'have',
      'has',
      'had',
      'do',
      'does',
      'did',
      'will',
      'would',
      'should',
      'could',
      'may',
      'might',
      'must',
      'can',
      'this',
      'that',
      'these',
      'those',
      'i',
      'you',
      'he',
      'she',
      'it',
      'we',
      'they',
      'me',
      'him',
      'her',
      'us',
      'them',
      'my',
      'your',
      'his',
      'its',
      'our',
      'their',
      'what',
      'which',
      'who',
      'whom',
      'whose',
      'where',
      'when',
      'why',
      'how',
      'all',
      'each',
      'every',
      'both',
      'few',
      'more',
      'most',
      'other',
      'some',
      'such',
      'no',
      'nor',
      'not',
      'only',
      'own',
      'same',
      'so',
      'than',
      'too',
      'very',
      'just',
      'now',
      'then',
      'here',
      'there',
    };

    // Extract words
    final words = transcript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2 && !stopWords.contains(word))
        .toList();

    // Count frequencies
    final frequencyMap = <String, int>{};
    for (final word in words) {
      frequencyMap[word] = (frequencyMap[word] ?? 0) + 1;
    }

    // Sort by frequency and get top 30
    final sortedWords = frequencyMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxFreq = sortedWords.isNotEmpty
        ? sortedWords.first.value.toDouble()
        : 1.0;

    return sortedWords.take(30).map((entry) {
      return WordFrequency(
        word: entry.key,
        frequency: entry.value,
        weight: entry.value / maxFreq,
      );
    }).toList();
  }

  /// Generate sentiment trend data points from messages
  SentimentTrend _generateSentimentTrend(
    List<TranscriptMessage> messages,
    double totalDuration,
  ) {
    final dataPoints = <SentimentDataPoint>[];

    if (messages.isEmpty || totalDuration <= 0) {
      // Return default trend with at least 3 points for chart visibility
      return SentimentTrend(
        dataPoints: [
          SentimentDataPoint(timestamp: 0.0, sentiment: 0.0),
          SentimentDataPoint(timestamp: 10.0, sentiment: 0.0),
          SentimentDataPoint(timestamp: 20.0, sentiment: 0.0),
        ],
      );
    }

    // Generate data points at regular intervals (every 10 seconds or per message)
    // Ensure we have at least 3-5 data points for better visualization
    final targetPoints = messages.length.clamp(3, 20);
    final interval = totalDuration / targetPoints;
    double currentTime = 0.0;
    int messageIndex = 0;

    while (currentTime <= totalDuration && messageIndex < messages.length) {
      final message = messages[messageIndex];
      final text = message.text.toLowerCase();

      // Calculate sentiment based on keywords
      double sentiment = 0.0;
      int positiveCount = 0;
      int negativeCount = 0;

      final positiveWords = [
        'thank',
        'great',
        'perfect',
        'happy',
        'good',
        'excellent',
        'satisfied',
        'pleased',
        'appreciate',
      ];
      final negativeWords = [
        'problem',
        'issue',
        'delayed',
        'urgent',
        'angry',
        'frustrated',
        'disappointed',
        'wrong',
        'bad',
        'terrible',
      ];

      for (final word in positiveWords) {
        if (text.contains(word)) positiveCount++;
      }
      for (final word in negativeWords) {
        if (text.contains(word)) negativeCount++;
      }

      if (positiveCount > negativeCount) {
        sentiment = 0.5 + (positiveCount * 0.1).clamp(0.0, 0.5);
      } else if (negativeCount > positiveCount) {
        sentiment = -0.5 - (negativeCount * 0.1).clamp(0.0, 0.5);
      } else {
        sentiment = 0.0;
      }

      // Use message sentiment if available
      if (message.sentiment != null) {
        sentiment = message.sentiment!;
      }

      dataPoints.add(
        SentimentDataPoint(
          timestamp: currentTime,
          sentiment: sentiment.clamp(-1.0, 1.0),
        ),
      );

      currentTime += interval;
      if (currentTime >=
          (messageIndex + 1) * (totalDuration / messages.length)) {
        messageIndex++;
      }
    }

    // Ensure at least 3 data points for chart visibility
    if (dataPoints.isEmpty) {
      dataPoints.addAll([
        SentimentDataPoint(timestamp: 0.0, sentiment: 0.0),
        SentimentDataPoint(timestamp: 10.0, sentiment: 0.0),
        SentimentDataPoint(timestamp: 20.0, sentiment: 0.0),
      ]);
    } else if (dataPoints.length == 1) {
      // If only one point, add two more for visibility
      final point = dataPoints.first;
      dataPoints.addAll([
        SentimentDataPoint(timestamp: point.timestamp + 10, sentiment: point.sentiment),
        SentimentDataPoint(timestamp: point.timestamp + 20, sentiment: point.sentiment),
      ]);
    } else if (dataPoints.length == 2) {
      // If only two points, add one more
      final lastPoint = dataPoints.last;
      dataPoints.add(
        SentimentDataPoint(timestamp: lastPoint.timestamp + 10, sentiment: lastPoint.sentiment),
      );
    }

    return SentimentTrend(dataPoints: dataPoints);
  }

  /// Extract key highlights from transcript when JSON parsing fails or fields are empty
  KeyHighlights _extractKeyHighlightsFromTranscript(
    String transcript,
    Map<String, dynamic>? highlightsData,
  ) {
    // Try to use data from highlightsData if available
    String issue = 'Issue identified in call';
    String resolution = 'Resolution discussed';
    String summary = 'Call summary';

    if (highlightsData != null) {
      issue = highlightsData['issue']?.toString().trim() ?? issue;
      resolution =
          highlightsData['resolution']?.toString().trim() ?? resolution;
      summary = highlightsData['summary']?.toString().trim() ?? summary;
    }

    // If fields are still empty or default, extract from transcript
    if (issue.isEmpty || issue == 'Issue identified in call') {
      // Try to find issue keywords in transcript
      final issueKeywords = [
        'problem',
        'issue',
        'complaint',
        'concern',
        'wrong',
        'error',
        'mistake',
      ];
      final transcriptLower = transcript.toLowerCase();
      for (final keyword in issueKeywords) {
        final index = transcriptLower.indexOf(keyword);
        if (index != -1) {
          // Extract sentence or phrase containing the keyword
          final start = index > 50 ? index - 50 : 0;
          final end = (index + 100 < transcript.length)
              ? index + 100
              : transcript.length;
          final snippet = transcript.substring(start, end).trim();
          if (snippet.length > 20) {
            issue = snippet;
            break;
          }
        }
      }
      // If still empty, use first part of transcript
      if (issue.isEmpty || issue == 'Issue identified in call') {
        issue = transcript.length > 150
            ? '${transcript.substring(0, 150).trim()}...'
            : transcript.trim();
      }
    }

    if (resolution.isEmpty || resolution == 'Resolution discussed') {
      // Try to find resolution keywords
      final resolutionKeywords = [
        'resolved',
        'fixed',
        'solved',
        'completed',
        'done',
        'agreed',
        'confirmed',
      ];
      final transcriptLower = transcript.toLowerCase();
      for (final keyword in resolutionKeywords) {
        final index = transcriptLower.indexOf(keyword);
        if (index != -1) {
          final start = index > 50 ? index - 50 : 0;
          final end = (index + 100 < transcript.length)
              ? index + 100
              : transcript.length;
          final snippet = transcript.substring(start, end).trim();
          if (snippet.length > 20) {
            resolution = snippet;
            break;
          }
        }
      }
      // If still empty, use middle part of transcript
      if (resolution.isEmpty || resolution == 'Resolution discussed') {
        final midPoint = transcript.length ~/ 2;
        resolution = transcript.length > 150
            ? '${transcript.substring(midPoint - 75, midPoint + 75).trim()}...'
            : transcript.substring(midPoint).trim();
      }
    }

    if (summary.isEmpty || summary == 'Call summary') {
      // Generate a more meaningful summary from transcript
      // Try to extract key sentences
      final sentences = transcript.split(RegExp(r'[.!?]\s+'));
      if (sentences.length > 3) {
        // Use first few sentences and last sentence
        final firstPart = sentences.take(2).join('. ').trim();
        final lastPart = sentences.last.trim();
        summary = '$firstPart. $lastPart.';
        // Limit length
        if (summary.length > 300) {
          summary = '${summary.substring(0, 300).trim()}...';
        }
      } else if (transcript.length > 200) {
        // Use first and last parts
        summary =
            '${transcript.substring(0, 150).trim()}... '
            '${transcript.substring(transcript.length - 100).trim()}';
      } else {
        summary = transcript.trim();
      }
    }

    return KeyHighlights(
      issue: issue.isNotEmpty ? issue : 'Issue identified in call',
      resolution: resolution.isNotEmpty ? resolution : 'Resolution discussed',
      summary: summary.isNotEmpty ? summary : 'Call summary',
    );
  }

  /// Extract topics from transcript using keyword matching
  List<TopicMention> _extractTopicsFromTranscript(String transcript) {
    final topicKeywords = {
      'Product Quality': [
        'quality',
        'defect',
        'broken',
        'damaged',
        'faulty',
        'issue with product',
      ],
      'Delivery Time': [
        'delivery',
        'shipping',
        'arrive',
        'late',
        'delay',
        'timeframe',
      ],
      'Price': [
        'price',
        'cost',
        'expensive',
        'cheap',
        'discount',
        'refund',
        'payment',
      ],
      'Billing': [
        'bill',
        'invoice',
        'charge',
        'billing',
        'payment',
        'transaction',
      ],
      'Technical Support': [
        'technical',
        'support',
        'help',
        'assistance',
        'troubleshoot',
        'error',
      ],
      'Customer Service': [
        'service',
        'complaint',
        'satisfaction',
        'experience',
        'support',
      ],
      'Warranty': [
        'warranty',
        'guarantee',
        'return',
        'exchange',
        'replacement',
      ],
      'Account': ['account', 'login', 'password', 'access', 'profile'],
    };

    final transcriptLower = transcript.toLowerCase();
    final topicCounts = <String, int>{};

    for (final entry in topicKeywords.entries) {
      int count = 0;
      for (final keyword in entry.value) {
        final regex = RegExp(r'\b' + keyword + r'\b', caseSensitive: false);
        count += regex.allMatches(transcriptLower).length;
      }
      if (count > 0) {
        topicCounts[entry.key] = count;
      }
    }

    if (topicCounts.isEmpty) {
      // Default topic if nothing found
      return [
        TopicMention(category: 'Customer Service', count: 1, percentage: 100.0),
      ];
    }

    final totalCount = topicCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return topicCounts.entries.map((entry) {
      return TopicMention(
        category: entry.key,
        count: entry.value,
        percentage: (entry.value / totalCount) * 100,
      );
    }).toList();
  }

  List<LoudnessDataPoint> _generateLoudnessTrend(
    List<TranscriptMessage> messages,
  ) {
    // Simulate loudness based on message length, sentiment, and speaker
    final dataPoints = <LoudnessDataPoint>[];
    double currentTime = 0.0;

    for (final message in messages) {
      final duration = message.duration?.inSeconds.toDouble() ?? 5.0;

      // Estimate loudness: longer messages or negative sentiment = higher loudness
      double loudness = 0.3; // Base loudness
      if (message.text.length > 100) {
        loudness += 0.2; // Longer messages might be louder
      }
      if (message.sentiment != null && message.sentiment! < 0) {
        loudness += 0.3; // Negative sentiment might indicate frustration
      }
      if (message.speaker.toLowerCase() == 'customer') {
        loudness += 0.1; // Customers might speak louder when upset
      }

      loudness = loudness.clamp(0.0, 1.0);

      // Add data points at start and end of message
      dataPoints.add(
        LoudnessDataPoint(timestamp: currentTime, loudness: loudness),
      );
      currentTime += duration;
      dataPoints.add(
        LoudnessDataPoint(timestamp: currentTime, loudness: loudness),
      );
    }

    return dataPoints;
  }

  /// Transcribe audio file using Gemini API
  Future<String> transcribeAudio(String audioPath) async {
    try {
      AppLogger.info('Transcribing audio: $audioPath');

      // Read audio bytes - handle web and mobile differently
      Uint8List audioBytes;
      String mimeType = 'audio/mpeg';

      if (kIsWeb) {
        // For web, check if it's a data URL
        if (audioPath.startsWith('data:')) {
          // Extract base64 data from data URL
          final commaIndex = audioPath.indexOf(',');
          final header = audioPath.substring(0, commaIndex);
          final base64Data = audioPath.substring(commaIndex + 1);

          // Extract mime type from header
          final mimeMatch = RegExp(r'data:([^;]+)').firstMatch(header);
          if (mimeMatch != null) {
            mimeType = mimeMatch.group(1) ?? 'audio/mpeg';
          }

          audioBytes = base64Decode(base64Data);
        } else if (audioPath.startsWith('assets/')) {
          // Handle asset paths on web - load asset and convert to data URL
          try {
            final assetPath = audioPath.replaceFirst('assets/', '');
            final byteData = await rootBundle.load(assetPath);
            audioBytes = byteData.buffer.asUint8List();

            // Determine mime type from extension
            final extension = audioPath.split('.').last.toLowerCase();
            mimeType = extension == 'm4a'
                ? 'audio/m4a'
                : extension == 'mp3'
                ? 'audio/mpeg'
                : extension == 'wav'
                ? 'audio/wav'
                : 'audio/mpeg';

            AppLogger.info(
              'Loaded asset audio file: $assetPath (${audioBytes.length} bytes)',
            );
          } catch (e) {
            throw Exception('Unable to load asset audio file: $e');
          }
        } else {
          throw Exception('Web audio path must be a data URL or asset path');
        }
      } else {
        // For mobile platforms - read file directly
        final file = File(audioPath);
        audioBytes = await file.readAsBytes();

        // Determine mime type from extension
        final extension = audioPath.split('.').last.toLowerCase();
        mimeType = extension == 'm4a'
            ? 'audio/m4a'
            : extension == 'mp3'
            ? 'audio/mpeg'
            : extension == 'wav'
            ? 'audio/wav'
            : 'audio/mpeg';
      }

      final base64Audio = base64Encode(audioBytes);

      // Prepare transcription prompt
      const prompt = '''Transcribe this customer service call audio. 
Identify who is speaking (Agent or Customer) for each segment.
Format the transcription as follows:
AGENT: [what the agent said]
CUSTOMER: [what the customer said]
AGENT: [next agent statement]
CUSTOMER: [next customer statement]
...

Provide a clear, accurate transcription with proper speaker identification.''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': mimeType, 'data': base64Audio},
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        },
      };

      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          receiveTimeout: const Duration(seconds: 180),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final transcript =
            response
                .data['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
            '';
        AppLogger.info('Audio transcription completed');
        return transcript;
      } else {
        throw Exception('Failed to transcribe audio: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error transcribing audio', e);
      rethrow;
    }
  }

  /// Parse transcript into structured messages
  List<TranscriptMessage> parseTranscript(String transcript) {
    final messages = <TranscriptMessage>[];
    final lines = transcript.split('\n');

    DateTime currentTime = DateTime.now();
    String? currentSpeaker;
    String currentText = '';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Try to parse timestamp and speaker
      final timestampMatch = RegExp(
        r'\[(\d{2}):(\d{2}):(\d{2})\]',
      ).firstMatch(trimmed);
      final speakerMatch = RegExp(
        r'(AGENT|CUSTOMER|Agent|Customer):',
      ).firstMatch(trimmed);

      if (timestampMatch != null && speakerMatch != null) {
        // Save previous message if exists
        if (currentSpeaker != null && currentText.isNotEmpty) {
          messages.add(
            TranscriptMessage(
              speaker: currentSpeaker.toLowerCase(),
              text: currentText.trim(),
              timestamp: currentTime,
            ),
          );
        }

        // Parse new message
        final hours = int.parse(timestampMatch.group(1)!);
        final minutes = int.parse(timestampMatch.group(2)!);
        final seconds = int.parse(timestampMatch.group(3)!);
        currentTime = DateTime.now().subtract(
          Duration(hours: hours, minutes: minutes, seconds: seconds),
        );
        currentSpeaker = speakerMatch.group(1)!.toLowerCase();
        currentText = trimmed.substring(speakerMatch.end).trim();
      } else if (currentSpeaker != null) {
        // Continuation of current message
        currentText += ' $trimmed';
      }
    }

    // Add last message
    if (currentSpeaker != null && currentText.isNotEmpty) {
      messages.add(
        TranscriptMessage(
          speaker: currentSpeaker,
          text: currentText.trim(),
          timestamp: currentTime,
        ),
      );
    }

    // If no structured format found, create a single message
    if (messages.isEmpty) {
      messages.add(
        TranscriptMessage(
          speaker: 'agent',
          text: transcript,
          timestamp: DateTime.now(),
        ),
      );
    }

    return messages;
  }
}
