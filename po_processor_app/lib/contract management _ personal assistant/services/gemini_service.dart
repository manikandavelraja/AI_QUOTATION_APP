import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' if (dart.library.html) '../io_stub.dart';
import 'package:dio/dio.dart';
import '../models/analysis_result.dart';
import '../models/meeting_analysis_result.dart';
import '../utils/logger.dart';
import '../utils/config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GeminiService {
  final Dio _dio = Dio();
  final String _apiKey = Config.geminiApiKey;
  final String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  GeminiService() {
    // Set longer timeouts for AI operations which can take time
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout =
        const Duration(seconds: 120); // 2 minutes for image/PDF/voice analysis
    _dio.options.sendTimeout = const Duration(seconds: 60);
  }

  Future<AnalysisResult> analyzeImage(String imagePath,
      {String languageCode = 'en'}) async {
    try {
      AppLogger.info('Analyzing image: $imagePath in language: $languageCode');

      // Read image bytes - handle web and mobile differently
      Uint8List imageBytes;
      String mimeType = 'image/png';

      if (kIsWeb) {
        // For web, check if it's a data URL
        if (imagePath.startsWith('data:')) {
          // Extract base64 data from data URL
          final commaIndex = imagePath.indexOf(',');
          final header = imagePath.substring(0, commaIndex);
          final base64Data = imagePath.substring(commaIndex + 1);

          // Extract mime type from header
          final mimeMatch = RegExp(r'data:([^;]+)').firstMatch(header);
          if (mimeMatch != null) {
            mimeType = mimeMatch.group(1) ?? 'image/png';
          }

          imageBytes = base64Decode(base64Data);
        } else {
          // Try to fetch as URL
          try {
            final response = await _dio.get<Uint8List>(
              imagePath,
              options: Options(responseType: ResponseType.bytes),
            );
            imageBytes = response.data ?? Uint8List(0);
          } catch (e) {
            throw Exception('Unable to read image: $e');
          }
        }
      } else {
        // For mobile platforms - read file directly using dart:io
        // Note: On mobile, imagePath is a file path string
        final file = File(imagePath);
        imageBytes = await file.readAsBytes();

        // Determine mime type from extension
        final extension = imagePath.split('.').last.toLowerCase();
        mimeType = extension == 'png'
            ? 'image/png'
            : extension == 'jpg' || extension == 'jpeg'
                ? 'image/jpeg'
                : 'image/png';
      }

      final base64Image = base64Encode(imageBytes);

      // Get language name for prompt
      String languageName = 'English';
      switch (languageCode) {
        case 'ta':
          languageName = 'Tamil';
          break;
        case 'hi':
          languageName = 'Hindi';
          break;
        default:
          languageName = 'English';
      }

      // Prepare the request
      final prompt = '''
Analyze this handwritten image with 100% accuracy. The image may contain text in English, Tamil, Hindi, or other regional languages.

IMPORTANT: Provide ALL your responses (summary and detailedContent) in $languageName language. If the user has selected $languageName, respond entirely in $languageName.

Provide your response in the following JSON format:
{
  "summary": "A two-line summary of the image content in $languageName",
  "detailedContent": "Very precise content without missing even a single character. Preserve the exact text as written, including spacing, line breaks, and punctuation. All text should be in $languageName.",
  "confidenceScore": 0.95
}

Instructions:
1. Parse the handwritten text with extreme accuracy
2. Provide ALL responses in $languageName language
3. If the original text is in a different language, transcribe it accurately but provide your analysis and summary in $languageName
4. Include every single character without omission
5. Maintain original formatting, spacing, and structure
6. Provide a confidence score between 0 and 1
7. Ensure summary and detailedContent are both in $languageName
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': mimeType, 'data': base64Image}
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        }
      };

      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout:
              const Duration(seconds: 180), // 3 minutes for image analysis
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data['candidates']?[0]?['content']?['parts']
                ?[0]?['text'] ??
            '';

        AppLogger.info('Received response from Gemini API');

        // Try to parse JSON from response
        AnalysisResult result = _parseResponse(content, imagePath);

        return result;
      } else {
        throw Exception('Invalid response from API: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error in GeminiService.analyzeImage', e);
      rethrow;
    }
  }

  AnalysisResult _parseResponse(String content, String imagePath) {
    try {
      // Try to extract JSON from markdown code blocks
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

      // Try to parse as JSON
      try {
        final jsonData = jsonDecode(jsonString);
        return AnalysisResult(
          summary: jsonData['summary'] ?? 'Summary not available',
          detailedContent: jsonData['detailedContent'] ?? content,
          confidenceScore: (jsonData['confidenceScore'] ?? 0.8).toDouble(),
          imagePath: imagePath,
          timestamp: DateTime.now(),
        );
      } catch (e) {
        // If JSON parsing fails, extract information from text
        AppLogger.warning('Could not parse JSON, extracting from text');
        return _extractFromText(content, imagePath);
      }
    } catch (e) {
      AppLogger.error('Error parsing response', e);
      // Return a default result if parsing fails
      return AnalysisResult(
        summary: 'Analysis completed, but parsing encountered an issue',
        detailedContent: content,
        confidenceScore: 0.5,
        imagePath: imagePath,
        timestamp: DateTime.now(),
      );
    }
  }

  AnalysisResult _extractFromText(String content, String imagePath) {
    // Try to extract summary and detailed content from text response
    String summary = '';
    String detailedContent = content;
    double confidenceScore = 0.8;

    // Look for summary patterns
    final summaryMatch = RegExp(
            r'(?:summary|Summary)[\s:]+(.+?)(?:\n\n|\n\d+\.|$)',
            caseSensitive: false)
        .firstMatch(content);
    if (summaryMatch != null) {
      summary = summaryMatch.group(1) ?? '';
    }

    // Look for confidence score
    final confidenceMatch = RegExp(
            r'(?:confidence|Confidence)[\s:]+(\d+\.?\d*)',
            caseSensitive: false)
        .firstMatch(content);
    if (confidenceMatch != null) {
      confidenceScore =
          double.tryParse(confidenceMatch.group(1) ?? '0.8') ?? 0.8;
    }

    // If no summary found, use first two lines
    if (summary.isEmpty) {
      final lines = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(2)
          .toList();
      summary = lines.join(' ');
      if (lines.length > 1) {
        detailedContent = content
            .substring(content.indexOf(lines[1]) + lines[1].length)
            .trim();
      }
    }

    return AnalysisResult(
      summary: summary.isNotEmpty ? summary : 'Content analysis completed',
      detailedContent: detailedContent.isNotEmpty ? detailedContent : content,
      confidenceScore: confidenceScore,
      imagePath: imagePath,
      timestamp: DateTime.now(),
    );
  }

  /// Process voice/audio file and convert to text using Gemini, returning AnalysisResult
  Future<AnalysisResult> processVoiceAudio(String audioPath,
      {String languageCode = 'en'}) async {
    try {
      AppLogger.info(
          'Processing voice audio: $audioPath in language: $languageCode');

      // Read audio bytes - handle web and mobile differently
      Uint8List audioBytes;
      String mimeType = 'audio/m4a';

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
            mimeType = mimeMatch.group(1) ?? 'audio/m4a';
          }

          audioBytes = base64Decode(base64Data);
        } else {
          // Try to fetch as URL
          try {
            final response = await _dio.get<Uint8List>(
              audioPath,
              options: Options(responseType: ResponseType.bytes),
            );
            audioBytes = response.data ?? Uint8List(0);
          } catch (e) {
            throw Exception('Unable to read audio: $e');
          }
        }
      } else {
        // For mobile platforms - read file directly using dart:io
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
                    : 'audio/m4a';
      }

      final base64Audio = base64Encode(audioBytes);

      // Get language name for prompt
      String languageName = 'English';
      switch (languageCode) {
        case 'ta':
          languageName = 'Tamil';
          break;
        case 'hi':
          languageName = 'Hindi';
          break;
        default:
          languageName = 'English';
      }

      // Prepare the request with same format as image analysis
      final prompt = '''
Analyze this audio recording with 100% accuracy. The audio may contain speech in English, Tamil, Hindi, or other regional languages.

IMPORTANT: Provide ALL your responses (summary and detailedContent) in $languageName language. If the user has selected $languageName, respond entirely in $languageName.

Provide your response in the following JSON format:
{
  "summary": "A two-line summary of the audio content in $languageName",
  "detailedContent": "Very precise transcription without missing even a single word. Preserve the exact speech as spoken, including spacing, pauses, and punctuation. All text should be in $languageName.",
  "confidenceScore": 0.95
}

Instructions:
1. Transcribe the speech with extreme accuracy
2. Provide ALL responses in $languageName language
3. If the original speech is in a different language, transcribe it accurately but provide your analysis and summary in $languageName
4. Include every single word without omission
5. Maintain proper punctuation and sentence structure
6. Provide a confidence score between 0 and 1
7. Ensure summary and detailedContent are both in $languageName
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': mimeType, 'data': base64Audio}
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        }
      };

      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout:
              const Duration(seconds: 180), // 3 minutes for voice analysis
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data['candidates']?[0]?['content']?['parts']
                ?[0]?['text'] ??
            '';

        AppLogger.info('Received response from Gemini API for voice');

        // Parse response similar to image analysis
        AnalysisResult result = _parseVoiceResponse(content, audioPath);

        return result;
      } else {
        throw Exception('Invalid response from API: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error in GeminiService.processVoiceAudio', e);
      rethrow;
    }
  }

  AnalysisResult _parseVoiceResponse(String content, String audioPath) {
    try {
      // Try to extract JSON from markdown code blocks
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

      // Try to parse as JSON
      try {
        final jsonData = jsonDecode(jsonString);
        return AnalysisResult(
          summary: jsonData['summary'] ?? 'Summary not available',
          detailedContent: jsonData['detailedContent'] ?? content,
          confidenceScore: (jsonData['confidenceScore'] ?? 0.8).toDouble(),
          imagePath: audioPath, // Using imagePath field to store audio path
          timestamp: DateTime.now(),
        );
      } catch (e) {
        // If JSON parsing fails, extract information from text
        AppLogger.warning(
            'Could not parse JSON for voice, extracting from text');
        return _extractVoiceFromText(content, audioPath);
      }
    } catch (e) {
      AppLogger.error('Error parsing voice response', e);
      // Return a default result if parsing fails
      return AnalysisResult(
        summary:
            'Voice transcription completed, but parsing encountered an issue',
        detailedContent: content,
        confidenceScore: 0.5,
        imagePath: audioPath,
        timestamp: DateTime.now(),
      );
    }
  }

  AnalysisResult _extractVoiceFromText(String content, String audioPath) {
    // Try to extract summary and detailed content from text response
    String summary = '';
    String detailedContent = content;
    double confidenceScore = 0.8;

    // Look for summary patterns
    final summaryMatch = RegExp(
            r'(?:summary|Summary)[\s:]+(.+?)(?:\n\n|\n\d+\.|$)',
            caseSensitive: false)
        .firstMatch(content);
    if (summaryMatch != null) {
      summary = summaryMatch.group(1) ?? '';
    }

    // Look for confidence score
    final confidenceMatch = RegExp(
            r'(?:confidence|Confidence)[\s:]+(\d+\.?\d*)',
            caseSensitive: false)
        .firstMatch(content);
    if (confidenceMatch != null) {
      confidenceScore =
          double.tryParse(confidenceMatch.group(1) ?? '0.8') ?? 0.8;
    }

    // If no summary found, use first two lines
    if (summary.isEmpty) {
      final lines = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(2)
          .toList();
      summary = lines.join(' ');
      if (lines.length > 1) {
        detailedContent = content
            .substring(content.indexOf(lines[1]) + lines[1].length)
            .trim();
      }
    }

    return AnalysisResult(
      summary: summary.isNotEmpty ? summary : 'Voice transcription completed',
      detailedContent: detailedContent.isNotEmpty ? detailedContent : content,
      confidenceScore: confidenceScore,
      imagePath: audioPath,
      timestamp: DateTime.now(),
    );
  }

  /// Parse PDF file and extract important points
  Future<AnalysisResult> parsePDF(String pdfPath,
      {String languageCode = 'en'}) async {
    try {
      AppLogger.info('Parsing PDF: $pdfPath in language: $languageCode');

      // Read PDF bytes - handle web and mobile differently
      Uint8List pdfBytes;

      if (kIsWeb) {
        // For web, check if it's a data URL
        if (pdfPath.startsWith('data:')) {
          final commaIndex = pdfPath.indexOf(',');
          final base64Data = pdfPath.substring(commaIndex + 1);
          pdfBytes = base64Decode(base64Data);
        } else {
          try {
            final response = await _dio.get<Uint8List>(
              pdfPath,
              options: Options(responseType: ResponseType.bytes),
            );
            pdfBytes = response.data ?? Uint8List(0);
          } catch (e) {
            throw Exception('Unable to read PDF: $e');
          }
        }
      } else {
        // For mobile platforms - read file directly
        final file = File(pdfPath);
        pdfBytes = await file.readAsBytes();
      }

      final base64Pdf = base64Encode(pdfBytes);

      // Get language name for prompt
      String languageName = 'English';
      switch (languageCode) {
        case 'ta':
          languageName = 'Tamil';
          break;
        case 'hi':
          languageName = 'Hindi';
          break;
        default:
          languageName = 'English';
      }

      // Prepare the request
      final prompt = '''
Analyze this PDF document and extract the key information.

IMPORTANT: Provide ALL your responses (summary and detailedContent) in $languageName language. If the user has selected $languageName, respond entirely in $languageName.

Provide your response in the following JSON format:
{
  "summary": "A short summary highlighting the important points and key information from the PDF in $languageName",
  "detailedContent": "Complete text content extracted from the PDF without missing any information. All text should be in $languageName.",
  "confidenceScore": 0.95
}

Instructions:
1. Extract all text content from the PDF accurately
2. Provide ALL responses in $languageName language
3. If the original document is in a different language, extract it accurately but provide your analysis and summary in $languageName
4. Identify and highlight important points, key facts, and main topics
5. Provide a concise summary that captures the essence of the document
6. Include all details in the detailed content section
7. Preserve formatting and structure where possible
8. Provide a confidence score between 0 and 1
9. Ensure summary and detailedContent are both in $languageName
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'application/pdf',
                  'data': base64Pdf
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        }
      };

      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout:
              const Duration(seconds: 180), // 3 minutes for PDF analysis
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data['candidates']?[0]?['content']?['parts']
                ?[0]?['text'] ??
            '';

        AppLogger.info('Received response from Gemini API for PDF');

        // Parse response similar to image analysis
        AnalysisResult result = _parseResponse(content, pdfPath);

        return result;
      } else {
        throw Exception('Invalid response from API: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error in GeminiService.parsePDF', e);
      rethrow;
    }
  }

  /// Process short voice note for billing (precise transcription)
  Future<AnalysisResult> processShortVoiceNote(String audioPath,
      {String languageCode = 'en'}) async {
    try {
      AppLogger.info(
          'Processing short voice note: $audioPath in language: $languageCode');

      // Read audio bytes
      Uint8List audioBytes;
      String mimeType = 'audio/m4a';

      if (kIsWeb) {
        if (audioPath.startsWith('data:')) {
          final commaIndex = audioPath.indexOf(',');
          final header = audioPath.substring(0, commaIndex);
          final base64Data = audioPath.substring(commaIndex + 1);

          final mimeMatch = RegExp(r'data:([^;]+)').firstMatch(header);
          if (mimeMatch != null) {
            mimeType = mimeMatch.group(1) ?? 'audio/m4a';
          }

          audioBytes = base64Decode(base64Data);
        } else {
          try {
            final response = await _dio.get<Uint8List>(
              audioPath,
              options: Options(responseType: ResponseType.bytes),
            );
            audioBytes = response.data ?? Uint8List(0);
          } catch (e) {
            throw Exception('Unable to read audio: $e');
          }
        }
      } else {
        final file = File(audioPath);
        audioBytes = await file.readAsBytes();

        final extension = audioPath.split('.').last.toLowerCase();
        mimeType = extension == 'm4a'
            ? 'audio/m4a'
            : extension == 'mp3'
                ? 'audio/mpeg'
                : extension == 'wav'
                    ? 'audio/wav'
                    : 'audio/m4a';
      }

      final base64Audio = base64Encode(audioBytes);

      // Get language name for prompt
      String languageName = 'English';
      switch (languageCode) {
        case 'ta':
          languageName = 'Tamil';
          break;
        case 'hi':
          languageName = 'Hindi';
          break;
        default:
          languageName = 'English';
      }

      // Prepare the request for precise transcription
      final prompt = '''
Transcribe this short voice note with 100% accuracy. This is for billing purposes, so every word must be captured exactly as spoken without any omissions.

IMPORTANT: Provide ALL your responses (summary and detailedContent) in $languageName language. If the user has selected $languageName, respond entirely in $languageName.

Provide your response in the following JSON format:
{
  "summary": "A brief summary of what was said in $languageName",
  "detailedContent": "Complete, word-for-word transcription without missing even a single word. Include all numbers, dates, names, and technical terms exactly as spoken. All text should be in $languageName.",
  "confidenceScore": 0.95
}

Instructions:
1. Transcribe with extreme precision - no words should be omitted
2. Provide ALL responses in $languageName language
3. If the original speech is in a different language, transcribe it accurately but provide your analysis and summary in $languageName
4. Preserve all numbers, dates, amounts, and technical terms exactly
5. Include filler words, pauses, and corrections if spoken
6. Maintain proper punctuation and sentence structure
7. Provide a confidence score between 0 and 1
8. Ensure summary and detailedContent are both in $languageName
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': mimeType, 'data': base64Audio}
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        }
      };

      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(
              seconds: 180), // 3 minutes for voice note transcription
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data['candidates']?[0]?['content']?['parts']
                ?[0]?['text'] ??
            '';

        AppLogger.info(
            'Received response from Gemini API for short voice note');

        AnalysisResult result = _parseVoiceResponse(content, audioPath);

        return result;
      } else {
        throw Exception('Invalid response from API: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error in GeminiService.processShortVoiceNote', e);
      rethrow;
    }
  }

  /// Analyze meeting conversation with summary, popular words, and important points
  Future<MeetingAnalysisResult> analyzeMeetingConversation(String audioPath,
      {String languageCode = 'en'}) async {
    try {
      AppLogger.info(
          'Analyzing meeting conversation: $audioPath in language: $languageCode');

      // Read audio bytes
      Uint8List audioBytes;
      String mimeType = 'audio/m4a';

      if (kIsWeb) {
        if (audioPath.startsWith('data:')) {
          final commaIndex = audioPath.indexOf(',');
          final header = audioPath.substring(0, commaIndex);
          final base64Data = audioPath.substring(commaIndex + 1);

          final mimeMatch = RegExp(r'data:([^;]+)').firstMatch(header);
          if (mimeMatch != null) {
            mimeType = mimeMatch.group(1) ?? 'audio/m4a';
          }

          audioBytes = base64Decode(base64Data);
        } else {
          try {
            final response = await _dio.get<Uint8List>(
              audioPath,
              options: Options(responseType: ResponseType.bytes),
            );
            audioBytes = response.data ?? Uint8List(0);
          } catch (e) {
            throw Exception('Unable to read audio: $e');
          }
        }
      } else {
        final file = File(audioPath);
        audioBytes = await file.readAsBytes();

        final extension = audioPath.split('.').last.toLowerCase();
        mimeType = extension == 'm4a'
            ? 'audio/m4a'
            : extension == 'mp3'
                ? 'audio/mpeg'
                : extension == 'wav'
                    ? 'audio/wav'
                    : 'audio/m4a';
      }

      final base64Audio = base64Encode(audioBytes);

      // Prepare the request for meeting analysis
      final prompt = '''
Analyze this meeting conversation recording. Extract key information, important discussion points, and identify frequently used words.

Provide your response in the following JSON format:
{
  "summary": "A comprehensive summary of the meeting covering main topics, decisions made, and key outcomes",
  "detailedTranscription": "Complete transcription of the conversation",
  "importantPoints": ["Point 1", "Point 2", "Point 3"],
  "popularWords": ["word1", "word2", "word3"],
  "confidenceScore": 0.95
}

Instructions:
1. Transcribe the entire conversation accurately
2. Identify and list all important discussion points, decisions, and action items
3. Extract the most frequently used words (excluding common words like "the", "a", "is", etc.)
4. Provide a comprehensive summary highlighting:
   - Main topics discussed
   - Key decisions made
   - Action items and responsibilities
   - Important dates and deadlines
   - Any concerns or issues raised
5. List popular/important words that were frequently mentioned
6. Provide a confidence score between 0 and 1
''';

      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': mimeType, 'data': base64Audio}
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 8192,
        }
      };

      final response = await _dio.post(
        '$_baseUrl/models/gemini-2.5-flash:generateContent?key=$_apiKey',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout:
              const Duration(seconds: 180), // 3 minutes for meeting analysis
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final content = response.data['candidates']?[0]?['content']?['parts']
                ?[0]?['text'] ??
            '';

        AppLogger.info(
            'Received response from Gemini API for meeting analysis');

        return _parseMeetingResponse(content, audioPath);
      } else {
        throw Exception('Invalid response from API: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Error in GeminiService.analyzeMeetingConversation', e);
      rethrow;
    }
  }

  MeetingAnalysisResult _parseMeetingResponse(
      String content, String audioPath) {
    try {
      // Try to extract JSON from markdown code blocks
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

      // Try to parse as JSON
      try {
        final jsonData = jsonDecode(jsonString);
        return MeetingAnalysisResult(
          summary: jsonData['summary'] ?? 'Meeting analysis completed',
          detailedTranscription: jsonData['detailedTranscription'] ?? content,
          importantPoints: List<String>.from(jsonData['importantPoints'] ?? []),
          popularWords: List<String>.from(jsonData['popularWords'] ?? []),
          confidenceScore: (jsonData['confidenceScore'] ?? 0.8).toDouble(),
          audioPath: audioPath,
          timestamp: DateTime.now(),
        );
      } catch (e) {
        // If JSON parsing fails, extract information from text
        AppLogger.warning(
            'Could not parse JSON for meeting, extracting from text');
        return _extractMeetingFromText(content, audioPath);
      }
    } catch (e) {
      AppLogger.error('Error parsing meeting response', e);
      return MeetingAnalysisResult(
        summary: 'Meeting analysis completed, but parsing encountered an issue',
        detailedTranscription: content,
        importantPoints: [],
        popularWords: [],
        confidenceScore: 0.5,
        audioPath: audioPath,
        timestamp: DateTime.now(),
      );
    }
  }

  MeetingAnalysisResult _extractMeetingFromText(
      String content, String audioPath) {
    String summary = '';
    String detailedTranscription = content;
    List<String> importantPoints = [];
    List<String> popularWords = [];
    double confidenceScore = 0.8;

    // Try to extract summary
    final summaryMatch = RegExp(
            r'(?:summary|Summary)[\s:]+(.+?)(?:\n\n|\n(?:important|popular|detailed))',
            caseSensitive: false,
            dotAll: true)
        .firstMatch(content);
    if (summaryMatch != null) {
      summary = summaryMatch.group(1)?.trim() ?? '';
    }

    // Try to extract important points
    final pointsMatch = RegExp(
            r'(?:important points?|key points?)[\s:]+(.+?)(?:\n\n|\n(?:popular|summary|detailed))',
            caseSensitive: false,
            dotAll: true)
        .firstMatch(content);
    if (pointsMatch != null) {
      final pointsText = pointsMatch.group(1) ?? '';
      importantPoints = pointsText
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.trim().replaceAll(RegExp(r'^[-•\d.\s]+'), ''))
          .where((line) => line.isNotEmpty)
          .toList();
    }

    // Try to extract popular words
    final wordsMatch = RegExp(
            r'(?:popular words?|frequent words?)[\s:]+(.+?)(?:\n\n|$)',
            caseSensitive: false,
            dotAll: true)
        .firstMatch(content);
    if (wordsMatch != null) {
      final wordsText = wordsMatch.group(1) ?? '';
      popularWords = wordsText
          .split(RegExp(r'[,;\n]'))
          .map((word) => word.trim())
          .where((word) => word.isNotEmpty)
          .toList();
    }

    // If no summary found, use first paragraph
    if (summary.isEmpty) {
      final lines = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(3)
          .toList();
      summary = lines.join(' ');
    }

    return MeetingAnalysisResult(
      summary: summary.isNotEmpty ? summary : 'Meeting analysis completed',
      detailedTranscription: detailedTranscription,
      importantPoints: importantPoints,
      popularWords: popularWords,
      confidenceScore: confidenceScore,
      audioPath: audioPath,
      timestamp: DateTime.now(),
    );
  }
}
