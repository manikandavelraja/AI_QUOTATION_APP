import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../domain/entities/quotation.dart';

class GeminiAIService {
  // Singleton instance
  static final GeminiAIService _instance = GeminiAIService._internal();
  factory GeminiAIService() => _instance;
  GeminiAIService._internal() {
    // Initialize with latest google_generative_ai package
    _model = GenerativeModel(
      model: AppConstants.geminiModel,
      apiKey: AppConstants.geminiApiKey,
    );
    
    // Initialize model with JSON response support for combined extraction
    _jsonModel = GenerativeModel(
      model: AppConstants.geminiModel,
      apiKey: AppConstants.geminiApiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        maxOutputTokens: 2048
      ),
  
    );
    debugPrint('✅ GeminiAIService initialized with model: ${AppConstants.geminiModel}');
  }

  late final GenerativeModel _model;
  late final GenerativeModel _jsonModel;
  
  // ========== COMPREHENSIVE RATE LIMITING SYSTEM ==========
  // Global rate limiting (shared across all instances)
  static DateTime? _lastApiCall;
  static const Duration _minDelayBetweenCalls = Duration(seconds: 30); // Increased to 30 seconds for free tier (20 req/day = ~1 req/72 min)
  
  // Request queue to serialize API calls
  static final List<Completer<void>> _requestQueue = [];
  static bool _isProcessingQueue = false;
  
  // Lock to prevent concurrent API calls
  static Completer<void>? _currentCall;
  
  // Rate limit tracking (per minute)
  static final List<DateTime> _requestHistory = []; // Track requests in last minute
  static const int _maxRequestsPerMinute = 1; // Only 1 request per minute for free tier safety
  static const Duration _rateLimitWindow = Duration(minutes: 1);
  
  // Daily quota tracking (FREE TIER: 20 requests per day)
  static final List<DateTime> _dailyRequestHistory = []; // Track requests today
  static const int _maxRequestsPerDay = 15; // Conservative: 15/day to stay under 20/day free tier limit
  static DateTime? _lastDailyReset;
  
  // Token tracking for TPM limits
  static int _tokensUsedInLastMinute = 0;
  static const int _maxTokensPerMinute = 100000; // Conservative limit
  static DateTime? _tokenResetTime;
  
  // Rate limit backoff state
  static DateTime? _rateLimitBackoffUntil;
  static const Duration _rateLimitBackoffDuration = Duration(hours: 24); // Wait 24 hours after hitting daily quota
  
  // Quota exceeded flag (for free tier daily limit)
  static bool _quotaExceeded = false;
  static DateTime? _quotaExceededUntil;

  /// Detect and log rate limit type (TPM vs RPM) from error message
  String _detectRateLimitType(String errorMessage, String errorString) {
    // Check for TPM (Tokens Per Minute) indicators
    if (errorString.contains('tpm') || 
        errorString.contains('tokens per minute') ||
        errorString.contains('token') && errorString.contains('minute')) {
      debugPrint('🔴 Rate Limit Type Detected: TPM (Tokens Per Minute)');
      return 'TPM';
    }
    
    // Check for RPM (Requests Per Minute) indicators
    if (errorString.contains('rpm') || 
        errorString.contains('requests per minute') ||
        errorString.contains('request') && errorString.contains('minute')) {
      debugPrint('🔴 Rate Limit Type Detected: RPM (Requests Per Minute)');
      return 'RPM';
    }
    
    // Check for RPD (Requests Per Day) indicators
    if (errorString.contains('rpd') || 
        errorString.contains('requests per day') ||
        errorString.contains('daily')) {
      debugPrint('🔴 Rate Limit Type Detected: RPD (Requests Per Day)');
      return 'RPD';
    }
    
    // Default to unknown
    debugPrint('⚠️ Rate Limit Type: Unknown (assuming general rate limit)');
    return 'UNKNOWN';
  }

  /// Clean up old request history entries
  static void _cleanupRequestHistory() {
    final now = DateTime.now();
    _requestHistory.removeWhere((timestamp) => 
        now.difference(timestamp) > _rateLimitWindow);
    
    // Clean up daily request history (remove entries older than 24 hours)
    _dailyRequestHistory.removeWhere((timestamp) => 
        now.difference(timestamp) > const Duration(hours: 24));
    
    // Reset daily counter if it's a new day
    if (_lastDailyReset == null || 
        now.difference(_lastDailyReset!) > const Duration(hours: 24)) {
      _dailyRequestHistory.clear();
      _lastDailyReset = now;
      _quotaExceeded = false;
      _quotaExceededUntil = null;
      debugPrint('🔄 Daily quota reset - new day started');
    }
    
    // Reset token count if window has passed
    if (_tokenResetTime != null && now.difference(_tokenResetTime!) > _rateLimitWindow) {
      _tokensUsedInLastMinute = 0;
      _tokenResetTime = now;
    } else if (_tokenResetTime == null) {
      _tokenResetTime = now;
    }
  }
  
  /// Check if we're currently rate limited
  static bool _isRateLimited() {
    final now = DateTime.now();
    
    // Clean up old history first
    _cleanupRequestHistory();
    
    // Check if quota is exceeded (free tier daily limit)
    if (_quotaExceeded) {
      if (_quotaExceededUntil != null && now.isBefore(_quotaExceededUntil!)) {
        final remaining = _quotaExceededUntil!.difference(now);
        debugPrint('🚫 Daily quota exceeded. Wait ${remaining.inHours} hours ${(remaining.inMinutes % 60)} minutes.');
        return true;
      } else {
        // Quota should have reset
        _quotaExceeded = false;
        _quotaExceededUntil = null;
      }
    }
    
    // Check if we're in backoff period
    if (_rateLimitBackoffUntil != null && now.isBefore(_rateLimitBackoffUntil!)) {
      final remaining = _rateLimitBackoffUntil!.difference(now);
      debugPrint('⏳ Rate limit backoff active. Wait ${remaining.inSeconds} more seconds.');
      return true;
    }
    
    // Check daily quota limit (FREE TIER: 20 requests/day)
    if (_dailyRequestHistory.length >= _maxRequestsPerDay) {
      debugPrint('🚫 Daily quota limit reached: ${_dailyRequestHistory.length}/$_maxRequestsPerDay requests today');
      debugPrint('⏰ Daily quota resets in ${_getTimeUntilDailyReset().inHours} hours');
      return true;
    }
    
    // Check RPM limit
    if (_requestHistory.length >= _maxRequestsPerMinute) {
      debugPrint('⚠️ RPM limit reached: ${_requestHistory.length}/$_maxRequestsPerMinute requests in last minute');
      return true;
    }
    
    // Check TPM limit (rough estimate)
    if (_tokensUsedInLastMinute >= _maxTokensPerMinute) {
      debugPrint('⚠️ TPM limit reached: $_tokensUsedInLastMinute/$_maxTokensPerMinute tokens in last minute');
      return true;
    }
    
    return false;
  }
  
  /// Get time until daily reset
  static Duration _getTimeUntilDailyReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tomorrow.difference(now);
  }
  
  /// Wait until rate limit is cleared
  static Future<void> _waitForRateLimit() async {
    while (_isRateLimited()) {
      final now = DateTime.now();
      Duration waitTime;
      
      // If quota exceeded, wait until daily reset
      if (_quotaExceeded && _quotaExceededUntil != null && now.isBefore(_quotaExceededUntil!)) {
        waitTime = _quotaExceededUntil!.difference(now);
        // Don't wait more than 1 hour at a time (in case of errors)
        if (waitTime.inHours > 1) {
          waitTime = const Duration(hours: 1);
        }
      } else if (_rateLimitBackoffUntil != null && now.isBefore(_rateLimitBackoffUntil!)) {
        waitTime = _rateLimitBackoffUntil!.difference(now);
      } else if (_dailyRequestHistory.length >= _maxRequestsPerDay) {
        // Wait until daily reset
        waitTime = _getTimeUntilDailyReset();
        // Don't wait more than 1 hour at a time
        if (waitTime.inHours > 1) {
          waitTime = const Duration(hours: 1);
        }
      } else if (_requestHistory.isNotEmpty) {
        // Wait until oldest request is outside the window
        final oldestRequest = _requestHistory.first;
        final timeUntilOldestExpires = _rateLimitWindow - now.difference(oldestRequest);
        waitTime = timeUntilOldestExpires > Duration.zero 
            ? timeUntilOldestExpires 
            : _minDelayBetweenCalls;
      } else {
        waitTime = _minDelayBetweenCalls;
      }
      
      // Add a small buffer
      waitTime = Duration(seconds: waitTime.inSeconds + 5);
      
      if (waitTime.inHours > 0) {
        debugPrint('⏳ Waiting ${waitTime.inHours}h ${(waitTime.inMinutes % 60)}m for rate limit to clear...');
      } else {
        debugPrint('⏳ Waiting ${waitTime.inSeconds} seconds for rate limit to clear...');
      }
      await Future.delayed(waitTime);
      _cleanupRequestHistory();
    }
  }
  
  /// Process request queue
  static Future<void> _processRequestQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    
    while (_requestQueue.isNotEmpty) {
      // Wait for rate limit to clear
      await _waitForRateLimit();
      
      // Process next request
      final completer = _requestQueue.removeAt(0);
      completer.complete();
      
      // Ensure minimum delay between requests
      if (_lastApiCall != null) {
        final timeSinceLastCall = DateTime.now().difference(_lastApiCall!);
        if (timeSinceLastCall < _minDelayBetweenCalls) {
          await Future.delayed(_minDelayBetweenCalls - timeSinceLastCall);
        }
      }
    }
    
    _isProcessingQueue = false;
  }
  
  /// Helper method to make API calls - RATE LIMITING REMOVED
  Future<String> _callWithRetry(Future<String> Function() apiCall, {int maxRetries = 3}) async {
    try {
      debugPrint('📤 Making API call (no rate limiting)...');
      
      // Simple retry logic without rate limiting
      int attemptCount = 0;
      return await retry(
        () async {
          attemptCount++;
          debugPrint('📤 API call attempt: $attemptCount/$maxRetries');
          
          try {
            final result = await apiCall();
            debugPrint('✅ API call successful');
            return result;
          } catch (e) {
            final errorString = e.toString().toLowerCase();
            
            // Only retry on network errors or 429 errors
            if (errorString.contains('429') ||
                errorString.contains('network') ||
                errorString.contains('timeout') ||
                errorString.contains('connection')) {
              debugPrint('🔄 Will retry: $errorString');
              rethrow;
            }
            
            // Don't retry other errors
            throw e;
          }
        },
        retryIf: (e) {
          final errorString = e.toString().toLowerCase();
          return (errorString.contains('429') ||
                  errorString.contains('network') ||
                  errorString.contains('timeout') ||
                  errorString.contains('connection')) &&
                 attemptCount < maxRetries;
        },
        maxAttempts: maxRetries,
        maxDelay: const Duration(seconds: 5),
        delayFactor: const Duration(seconds: 1),
      );
    } catch (e) {
      debugPrint('❌ API call failed: $e');
      rethrow;
    }
  }

  // ========== PDF TEXT SANITIZATION ==========
  /// Sanitize PDF text by removing technical headers, gibberish, and normalizing whitespace
  String sanitizePdfText(String rawText) {
    // 1. Remove PDF technical headers and object markers
    String cleanText = rawText.replaceAll(RegExp(r'(\%PDF-|obj|endobj|xref|trailer|startxref|[0-9]+\s[0-9]+\sobj)'), '');
    
    // 2. Remove long strings of non-alphanumeric "gibberish" seen in console
    cleanText = cleanText.replaceAll(RegExp(r'[^\x20-\x7E\n\t]'), ' '); 
    
    // 3. Collapse multiple spaces/newlines into single ones for token efficiency
    cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return cleanText;
  }

  /// Extract text from PDF bytes - Enhanced extraction with better text parsing
  Future<String> extractTextFromPDFBytes(Uint8List bytes, String fileName) async {
    try {
      debugPrint('=== STARTING PDF TEXT EXTRACTION ===');
      debugPrint('PDF file: $fileName, Size: ${bytes.length} bytes');
      
      // Step 1: Extract text directly from PDF bytes (handles compressed PDFs)
      debugPrint('📄 Step 1: Extracting text directly from PDF structure...');
      String extractedText = await _extractTextFromPDFAlternative(bytes, fileName);
      
      debugPrint('📄 Direct extraction result: ${extractedText.length} characters');
      
      // Step 2: Clean and validate extracted text
      if (extractedText.length > 200) {
        // Check if text looks readable (contains letters and common PO keywords)
        final hasReadableContent = RegExp(r'[a-zA-Z]{3,}').hasMatch(extractedText) &&
            (extractedText.toLowerCase().contains('po') ||
             extractedText.toLowerCase().contains('purchase') ||
             extractedText.toLowerCase().contains('order') ||
             extractedText.toLowerCase().contains('customer') ||
             extractedText.toLowerCase().contains('item') ||
             extractedText.toLowerCase().contains('total') ||
             RegExp(r'\d+\.\d{2}').hasMatch(extractedText)); // Has price-like numbers
        
        if (hasReadableContent) {
          debugPrint('✅ Direct extraction successful with readable content');
          // Sanitize the extracted text before returning
          final sanitizedText = sanitizePdfText(extractedText);
          debugPrint('First 1000 chars: ${sanitizedText.length > 1000 ? sanitizedText.substring(0, 1000) : sanitizedText}');
          return sanitizedText;
        }
      }
      
      // Step 3: If direct extraction didn't work well, use Gemini to extract from PDF structure
      debugPrint('⚠️ Direct extraction needs enhancement, using Gemini to extract readable text...');
      
      // Send the extracted text (even if minimal) to Gemini to extract readable content
      final extractionPrompt = '''
You are processing a Purchase Order PDF document. The PDF text extraction returned the following content, which may contain PDF metadata, technical information, or corrupted characters mixed with actual document text.

YOUR TASK: Extract ALL readable Purchase Order information from this text, ignoring PDF technical metadata, escape sequences, and corrupted characters.

CRITICAL INSTRUCTIONS:
1. Look for actual Purchase Order content, even if it's mixed with technical PDF data
2. Extract readable text that contains:
   - PO Number (look for patterns like "PO Number:", "PO:", "PO #", "Order No", etc.)
   - Date (look for "Date:", "PO Date:", "Order Date", etc.)
   - Customer Name (look for "Customer Name:", "Customer:", "Bill To:", etc.)
   - Line Items (look for tables with Item No, Description, Part Number, Qty, Unit Price, Total)
   - Grand Total (look for "Grand Total:", "Total Amount:", "Total:", etc.)
3. Ignore PDF commands, metadata, escape sequences (\\x, \\n, etc.), and technical information
4. Return ONLY the clean, readable Purchase Order text content
5. Preserve the structure and field names as they appear in the document

Extracted PDF text:
$extractedText

Extract and return ONLY the readable Purchase Order text content, removing all PDF technical metadata and corrupted characters.
''';
      
      final enhancedText = await _callWithRetry(() async {
        final result = await _model.generateContent([Content.text(extractionPrompt)])
            .timeout(const Duration(minutes: 2));
        return result.text ?? '';
      });
      
      if (enhancedText.isNotEmpty && enhancedText.length > 100) {
        debugPrint('✅ Gemini text extraction successful: ${enhancedText.length} characters');
        // Sanitize the enhanced text before returning
        final sanitizedText = sanitizePdfText(enhancedText);
        debugPrint('First 1000 chars: ${sanitizedText.length > 1000 ? sanitizedText.substring(0, 1000) : sanitizedText}');
        return sanitizedText;
      }
      
      // Step 4: Fallback - use direct extraction if Gemini didn't help
      if (extractedText.length > 50) {
        debugPrint('⚠️ Using direct extraction as fallback: ${extractedText.length} characters');
        // Sanitize the fallback text before returning
        return sanitizePdfText(extractedText);
      }
      
      throw Exception('Failed to extract readable text from PDF. The PDF may be corrupted, image-based, or password-protected. Please ensure the PDF contains selectable text.');
    } catch (e) {
      debugPrint('❌ Error in PDF text extraction: $e');
      rethrow;
    }
  }

  /// Alternative method to extract text from PDF
  Future<String> _extractTextFromPDFAlternative(Uint8List bytes, String fileName) async {
    try {
      debugPrint('=== EXTRACTING TEXT FROM PDF BYTES ===');
      final pdfString = String.fromCharCodes(bytes);
      
      final extractedText = StringBuffer();
      final seenText = <String>{};
      
      // Method 1: Extract text from parentheses (most common PDF text format)
      // Look for text in parentheses that contains readable content
      final textPattern = RegExp(r'\(([^)]+)\)', multiLine: true);
      final matches = textPattern.allMatches(pdfString);
      
      for (final match in matches) {
        final text = match.group(1);
        if (text != null && text.length > 1) {
          // Skip PDF commands and metadata
          if (!text.startsWith('/') && 
              !text.startsWith('\\') &&
              !text.contains('\\x') && 
              !RegExp(r'^[0-9\s\.\-]+$').hasMatch(text) && // Not just numbers
              text.length < 500 && // Reasonable text length
              RegExp(r'[a-zA-Z]').hasMatch(text)) { // Contains letters
            // Clean up escape sequences
            String cleanText = text
                .replaceAll('\\n', '\n')
                .replaceAll('\\r', '')
                .replaceAll('\\t', ' ')
                .replaceAll('\\040', ' ') // Space escape
                .replaceAllMapped(RegExp(r'\\([0-9]{3})'), (match) {
                  // Convert octal escapes to characters
                  try {
                    return String.fromCharCode(int.parse(match.group(1)!, radix: 8));
                  } catch (e) {
                    return '';
                  }
                })
                .replaceAll(RegExp(r'\\(.)'), r'$1') // Handle other escape sequences
                .trim();
            
            // Filter out non-printable characters but keep structure
            cleanText = cleanText.replaceAll(RegExp(r'[^\x20-\x7E\n\r]'), '');
            
            if (cleanText.length > 1 && 
                !cleanText.contains('\\x') &&
                !seenText.contains(cleanText)) {
              seenText.add(cleanText);
              extractedText.writeln(cleanText);
            }
          }
        }
      }
      
      // Method 2: Extract from BT/ET blocks (PDF text objects) - more reliable
      final btPattern = RegExp(r'BT\s+(.*?)\s+ET', dotAll: true);
      final btMatches = btPattern.allMatches(pdfString);
      for (final match in btMatches) {
        final content = match.group(1);
        if (content != null) {
          // Extract text from parentheses in BT/ET blocks
          final textMatches = RegExp(r'\(([^)]+)\)').allMatches(content);
          for (final textMatch in textMatches) {
            final text = textMatch.group(1);
            if (text != null && 
                text.length > 1 && 
                !text.startsWith('/') && 
                !text.contains('\\x') &&
                RegExp(r'[a-zA-Z]').hasMatch(text)) {
              String cleanText = text
                  .replaceAll('\\n', '\n')
                  .replaceAll('\\r', '')
                  .replaceAll('\\t', ' ')
                  .replaceAll(RegExp(r'\\(.)'), r'$1')
                  .trim();
              cleanText = cleanText.replaceAll(RegExp(r'[^\x20-\x7E\n\r]'), '');
              if (cleanText.length > 1 && !seenText.contains(cleanText)) {
                seenText.add(cleanText);
                extractedText.writeln(cleanText);
              }
            }
          }
        }
      }
      
      // Method 3: Extract readable ASCII sequences directly
      // Look for sequences of printable ASCII characters
      final asciiPattern = RegExp(r'[A-Za-z0-9\s\.,:;!?@#$%^&*()_+\-=\[\]{}|;"<>?/]{10,}');
      final asciiMatches = asciiPattern.allMatches(pdfString);
      for (final match in asciiMatches) {
        final text = match.group(0);
        if (text != null && 
            text.length > 10 &&
            RegExp(r'[a-zA-Z]').hasMatch(text) && // Contains letters
            !text.startsWith('/') &&
            !text.contains('\\x') &&
            !text.contains('stream') &&
            !text.contains('endstream') &&
            !text.contains('obj') &&
            !text.contains('endobj')) {
          final trimmed = text.trim();
          if (trimmed.length > 10 && !seenText.contains(trimmed)) {
            seenText.add(trimmed);
            extractedText.writeln(trimmed);
          }
        }
      }
      
      String result = extractedText.toString();
      
      // Clean up the result
      result = result
          .replaceAll(RegExp(r'[ \t]+'), ' ') // Normalize spaces
          .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n') // Normalize newlines
          .replaceAll(RegExp(r'[^\x20-\x7E\n\r]'), '') // Remove non-printable
          .trim();
      
      // Remove duplicate lines while preserving order
      final lines = result.split('\n');
      final uniqueLines = <String>{};
      final cleanedLines = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && 
            trimmed.length > 2 &&
            !uniqueLines.contains(trimmed) &&
            RegExp(r'[a-zA-Z0-9]').hasMatch(trimmed)) {
          uniqueLines.add(trimmed);
          cleanedLines.add(trimmed);
        }
      }
      result = cleanedLines.join('\n');
      
      debugPrint('=== EXTRACTED TEXT FROM PDF (${result.length} chars) ===');
      if (result.length > 0) {
        debugPrint('First 1000 chars: ${result.length > 1000 ? result.substring(0, 1000) : result}');
      }
      debugPrint('=== END EXTRACTED TEXT ===');
      
      return result;
    } catch (e) {
      debugPrint('Error in PDF text extraction: $e');
      return '';
    }
  }

  /// Extract PO data from PDF text
  Future<PurchaseOrder> extractPOData(String pdfText) async {
    try {
      // If pdfText is a placeholder or too short, throw error
      if (pdfText == 'PDF_CONTENT_EXTRACTION_REQUIRED' || 
          pdfText.isEmpty || 
          pdfText.length < 50 ||
          pdfText == 'Purchase Order PDF' ||
          pdfText.contains('Purchase Order PDF -')) {
        throw Exception('PDF text extraction failed. Please ensure the PDF contains readable text.');
      }
      
      // Sanitize PDF text before processing
      final sanitizedText = sanitizePdfText(pdfText);
      
      // Debug: Print first 500 chars to see what we're working with
      debugPrint('=== PDF TEXT EXTRACTED (first 500 chars, sanitized) ===');
      debugPrint(sanitizedText.length > 500 ? sanitizedText.substring(0, 500) : sanitizedText);
      debugPrint('=== END PDF TEXT ===');
      
      final prompt = _buildExtractionPrompt(sanitizedText);
      final extractedText = await _callWithRetry(() async {
        // Increased timeout to 2 minutes to account for processing time
        // Rate limiting is handled by _callWithRetry, so this timeout is just for the actual API call
        final result = await _model.generateContent([Content.text(prompt)])
            .timeout(const Duration(minutes: 2));
        return result.text ?? '';
      });
      if (extractedText.isEmpty) {
        throw Exception('AI did not return any data. Please try again.');
      }
      
      // Debug: Print AI response
      debugPrint('=== AI RESPONSE ===');
      debugPrint(extractedText.length > 1000 ? extractedText.substring(0, 1000) : extractedText);
      debugPrint('=== END AI RESPONSE ===');
      
      return _parseExtractedData(extractedText, sanitizedText);
    } catch (e) {
      debugPrint('ERROR in extractPOData: $e');
      throw Exception('Failed to extract PO data: $e');
    }
  }

  /// Generate English summary of PO
  Future<String> generateSummary(PurchaseOrder po) async {
    try {
      final prompt = _buildSummaryPrompt(po);
      final summary = await _callWithRetry(() async {
        final result = await _model.generateContent([Content.text(prompt)]);
        return result.text ?? 'Summary generation failed';
      });
      return summary;
    } catch (e) {
      throw Exception('Failed to generate summary: $e');
    }
  }

  /// REPLACEMENT METHOD: Direct PDF extraction using HTTP API with inline_data
  /// Uses inline_data format (equivalent to InlineDataPart) for true multimodal processing
  /// This tells Gemini to "look" at the document visually rather than just reading text
  /// Preserves layout and avoids garbled text extraction issues
  Future<Map<String, dynamic>> extractPOFromPDFBytes(Uint8List pdfBytes, String fileName) async {
    try {
      debugPrint('=== FIXING: Direct Multimodal Extraction with inline_data ===');
      debugPrint('PDF file: $fileName, Size: ${pdfBytes.length} bytes');

      // 1. Build the correct prompt for PDF visual processing
      final semanticPrompt = _buildSemanticExtractionPromptForPDF();

      // 2. Encode PDF bytes to base64
      final base64Pdf = base64Encode(pdfBytes);

      // 3. Build the request body with inline_data (equivalent to InlineDataPart)
      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'inline_data': {
                  'mime_type': 'application/pdf',
                  'data': base64Pdf,
                }
              },
              {
                'text': semanticPrompt,
              }
            ]
          }
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'maxOutputTokens': 2048,
        }
      };

      debugPrint('📤 Sending PDF using inline_data (equivalent to InlineDataPart)');
      debugPrint('📤 PDF size: ${pdfBytes.length} bytes, Base64 size: ${base64Pdf.length} chars');
      debugPrint('📤 This tells Gemini to process the PDF as a visual document (multimodal)');
      debugPrint('📤 Preserves layout and avoids garbled text extraction');

      // 4. Make HTTP request directly to Gemini API
      final response = await _callWithRetry(() async {
        debugPrint('📡 Making HTTP request to Gemini API with inline_data...');
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/${AppConstants.geminiModel}:generateContent?key=${AppConstants.geminiApiKey}',
        );

        final httpResponse = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        ).timeout(const Duration(minutes: 2));

        if (httpResponse.statusCode != 200) {
          throw Exception('API error: ${httpResponse.statusCode} - ${httpResponse.body}');
        }

        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        final candidates = responseJson['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No candidates in response');
        }

        final firstCandidate = candidates[0] as Map<String, dynamic>;
        final content = firstCandidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw Exception('No parts in response');
        }

        final textPart = parts[0] as Map<String, dynamic>?;
        final responseText = textPart?['text'] as String? ?? '';
        debugPrint('✅ Received response from API: ${responseText.length} characters');
        return responseText;
      });

      if (response.isEmpty) {
        debugPrint('❌ AI returned empty response');
        throw Exception('AI returned empty response. The PDF may be corrupted or unreadable.');
      }

      debugPrint('=== SEMANTIC EXTRACTION API RESPONSE ===');
      debugPrint(response.length > 2000 ? response.substring(0, 2000) : response);
      debugPrint('=== END RESPONSE ===');

      // 5. Parse the valid JSON
      final parsedResult = _parseSemanticResponse(response);
      debugPrint('✅ Successfully parsed response: isValid=${parsedResult['isValid']}');
      return parsedResult;

    } catch (e) {
      debugPrint('❌ Direct PDF extraction with inline_data failed: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      debugPrint('❌ Error details: ${e.toString()}');
      // Don't fall back to text extraction - rethrow to let caller handle
      rethrow;
    }
  }

  /// Combined method: Validate, Extract PO Data, and Generate Summary in a single API call
  /// This reduces RPM usage by combining 3 operations into 1 API call
  /// Uses text-based extraction (fallback method)
  Future<Map<String, dynamic>> validateExtractAndSummarize(String pdfText) async {
    try {
      // Basic validation - if text is too short, return early
      if (pdfText.isEmpty || pdfText.length < 50) {
        return {
          'isValid': false,
          'poData': null,
          'summary': 'Document text is too short or empty.',
        };
      }
      
      // Always call the API for proper validation and extraction
      // Don't do keyword checking here - let the AI determine if it's a valid PO
      // Direct PDF extraction might not contain exact keywords but could still be a valid PO
      debugPrint('=== COMBINED EXTRACTION: Validating, Extracting, and Summarizing ===');
      debugPrint('PDF Text length: ${pdfText.length} chars');
      
      // Use multi-format prompt for better format handling
      final prompt = _buildMultiFormatPrompt(pdfText);
      
      // Make single API call with JSON response
      final response = await _callWithRetry(() async {
        final result = await _jsonModel.generateContent([Content.text(prompt)])
            .timeout(const Duration(minutes: 2));
        
        // Check for content safety filters in response text
        final responseText = result.text ?? '';
        if (responseText.toLowerCase().contains('safety') || 
            responseText.toLowerCase().contains('blocked') ||
            responseText.toLowerCase().contains('restricted')) {
          debugPrint('⚠️ Content safety filter may have triggered');
        }
        
        return responseText;
      });
      
      if (response.isEmpty) {
        throw Exception('AI did not return any data. Please try again.');
      }
      
      debugPrint('=== COMBINED API RESPONSE ===');
      debugPrint(response.length > 1000 ? response.substring(0, 1000) : response);
      debugPrint('=== END RESPONSE ===');
      
      // Parse the JSON response
      String cleanJson = response.trim();
      // Remove markdown code blocks if present
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();
      
      Map<String, dynamic> jsonData;
      try {
        jsonData = json.decode(cleanJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('JSON parsing error: $e');
        debugPrint('Attempting to extract JSON from response...');
        // Try to find JSON object in the response
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleanJson);
        if (jsonMatch != null) {
          try {
            jsonData = json.decode(jsonMatch.group(0)!) as Map<String, dynamic>;
          } catch (e2) {
            debugPrint('Failed to parse extracted JSON: $e2');
            throw Exception('Failed to parse AI response. The response may be malformed.');
          }
        } else {
          throw Exception('No valid JSON found in AI response.');
        }
      }
      
      // Extract the three components
      final isValid = jsonData['isValid'] as bool? ?? false;
      final poDataJson = jsonData['poData'] as Map<String, dynamic>?;
      final summary = jsonData['summary'] as String? ?? '';
      
      PurchaseOrder? poData;
      // Try to extract data even if validation says false, or if validation is true
      if (poDataJson != null && poDataJson.isNotEmpty) {
        try {
          // Convert Map to JSON string and parse using existing method
          final jsonString = json.encode(poDataJson);
          poData = _parseExtractedData(jsonString, pdfText);
          debugPrint('✅ Successfully parsed PO data from JSON');
        } catch (e) {
          debugPrint('Error parsing PO data from JSON: $e');
          poData = null;
        }
      }
      
      // If we got data but validation said false, still return the data
      // This handles cases where AI is overly strict in validation
      if (poData != null && !isValid) {
        debugPrint('⚠️ Got PO data but validation was false. Using extracted data anyway.');
        return {
          'isValid': true, // Override validation since we have data
          'poData': poData,
          'summary': summary.isNotEmpty ? summary : 'Purchase Order extracted successfully.',
        };
      }
      
      // Even if validation is false and no data extracted, check if we can extract something
      // Sometimes the AI is too strict - try to extract basic info from the text
      if (!isValid && poData == null && pdfText.length > 100) {
        debugPrint('⚠️ Validation failed and no data extracted. Attempting fallback extraction...');
        try {
          // Try to extract at least basic info using regex patterns
          final poNumberMatch = RegExp(r'PO\s*(?:Number|#|No\.?)[\s:]*([A-Z0-9\-]+)', caseSensitive: false).firstMatch(pdfText);
          final dateMatch = RegExp(r'Date[\s:]*(\d{1,2}[\s/]\d{1,2}[\s/]\d{4}|\d{1,2}\s+\w+\s+\d{4})', caseSensitive: false).firstMatch(pdfText);
          final customerMatch = RegExp(r'Customer\s+Name[\s:]*([A-Za-z\s&]+)', caseSensitive: false).firstMatch(pdfText);
          final totalMatch = RegExp(r'Grand\s+Total[\s:]*([\d,]+\.?\d*)\s*([A-Z]{3})?', caseSensitive: false).firstMatch(pdfText);
          
          if (poNumberMatch != null || dateMatch != null || customerMatch != null || totalMatch != null) {
            debugPrint('✅ Found some PO data in text, attempting to create PO object...');
            // Try the regular extraction method as fallback
            try {
              final fallbackPoData = await extractPOData(pdfText).timeout(const Duration(seconds: 30));
              debugPrint('✅ Fallback extraction succeeded!');
              return {
                'isValid': true,
                'poData': fallbackPoData,
                'summary': 'Purchase Order extracted successfully using fallback method.',
              };
            } catch (e) {
              debugPrint('Fallback extraction failed: $e');
            }
          }
        } catch (e) {
          debugPrint('Fallback extraction failed: $e');
        }
      }
      
      return {
        'isValid': isValid,
        'poData': poData,
        'summary': summary,
      };
    } catch (e) {
      debugPrint('ERROR in validateExtractAndSummarize: $e');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error details: ${e.toString()}');
      
      // Check if it's a rate limit error - preserve that message
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('rate limit') || 
          errorString.contains('429') ||
          errorString.contains('rpm') ||
          errorString.contains('tpm') ||
          errorString.contains('rpd') ||
          errorString.contains('resource exhausted')) {
        rethrow; // Re-throw rate limit errors so they're handled properly upstream
      }
      
      // Fallback: try basic validation - be very lenient
      final lowerText = pdfText.toLowerCase();
      final basicValid = lowerText.contains('purchase order') || 
                         lowerText.contains('po number') ||
                         lowerText.contains('order number') ||
                         lowerText.contains('po-') ||
                         lowerText.contains('order no') ||
                         lowerText.contains('order #') ||
                         lowerText.contains('p.o.') ||
                         lowerText.contains('po #') ||
                         lowerText.contains('order id') ||
                         lowerText.contains('reference') ||
                         lowerText.contains('ref #') ||
                         (lowerText.contains('customer') && (lowerText.contains('total') || lowerText.contains('amount') || lowerText.contains('price'))) ||
                         (lowerText.contains('item') && (lowerText.contains('quantity') || lowerText.contains('qty'))) ||
                         (lowerText.contains('product') && lowerText.contains('price')) ||
                         (lowerText.contains('line item')) ||
                         (lowerText.contains('description') && lowerText.contains('quantity')) ||
                         (lowerText.contains('bill to') || lowerText.contains('ship to')) ||
                         (lowerText.contains('vendor') || lowerText.contains('supplier')) ||
                         // More lenient: if it has numbers that look like prices/amounts and some structure
                         (RegExp(r'\d+\.\d{2}').hasMatch(pdfText) && (lowerText.contains('total') || lowerText.contains('amount')));
      
      // Always try to extract data using the regular extraction method as a fallback
      // Don't require basicValid to be true - let the extraction method determine validity
      PurchaseOrder? fallbackPoData;
      if (pdfText.length > 100) {
        try {
          debugPrint('Attempting fallback extraction (regardless of basic validation)...');
          fallbackPoData = await extractPOData(pdfText).timeout(const Duration(seconds: 30));
          // If we get here, extraction succeeded (no exception thrown)
          debugPrint('✅ Fallback extraction succeeded!');
          return {
            'isValid': true,
            'poData': fallbackPoData,
            'summary': 'Purchase Order extracted successfully using fallback method.',
          };
        } catch (fallbackError) {
          debugPrint('Fallback extraction also failed: $fallbackError');
          fallbackPoData = null;
        }
      }
      
      // If extraction failed but basic validation passed, provide helpful message
      if (basicValid) {
        return {
          'isValid': false,
          'poData': fallbackPoData,
          'summary': 'Document appears to be a Purchase Order, but extraction failed. Please try again or check if the document format is supported. The document may be image-based (requiring OCR) or in an unsupported format.',
        };
      }
      
      // If both validation and extraction failed
      return {
        'isValid': false,
        'poData': fallbackPoData,
        'summary': 'Unable to process the document as a Purchase Order. Please ensure:\n'
            '- The PDF contains readable text (not just images)\n'
            '- The document includes purchase order information (order number, items, quantities, prices)\n'
            '- The document is not corrupted\n\n'
            'If your document is image-based, please use OCR to convert it to text first.',
      };
    }
  }

  /// Validate if uploaded file is a valid PO
  /// Test API connectivity with a simple call
  /// Returns true if API key is valid and working
  Future<bool> testApiConnection() async {
    try {
      debugPrint('🧪 Testing Gemini API connection...');
      final testPrompt = 'Say "API connection successful" in one sentence.';
      
      final response = await _callWithRetry(() async {
        final result = await _model.generateContent([Content.text(testPrompt)]);
        return result.text ?? '';
      });
      
      if (response.isNotEmpty && response.toLowerCase().contains('successful')) {
        debugPrint('✅ API connection test PASSED');
        return true;
      } else {
        debugPrint('⚠️ API connection test returned unexpected response: $response');
        return false;
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('api key') || 
          errorString.contains('invalid') ||
          errorString.contains('unauthorized') ||
          errorString.contains('403') ||
          errorString.contains('401')) {
        debugPrint('❌ API connection test FAILED: Invalid API key');
        throw Exception('Invalid API key. Please check your Gemini API key in app_constants.dart');
      } else if (errorString.contains('429') || errorString.contains('quota')) {
        debugPrint('⚠️ API connection test: Rate limited (this is expected if quota exceeded)');
        return true; // API key is valid, just rate limited
      } else {
        debugPrint('❌ API connection test FAILED: $e');
        throw Exception('API connection test failed: $e');
      }
    }
  }

  Future<bool> validatePOFile(String pdfText) async {
    try {
      // If text is too short or empty, assume it's not valid
      if (pdfText.isEmpty || pdfText.length < 50) {
        return false;
      }
      
      // Check for common PO keywords
      final lowerText = pdfText.toLowerCase();
      final hasPOKeywords = lowerText.contains('purchase order') ||
          lowerText.contains('po number') ||
          lowerText.contains('po-') ||
          lowerText.contains('order details') ||
          lowerText.contains('customer') ||
          lowerText.contains('line item');
      
      if (!hasPOKeywords) {
        return false;
      }
      
      // Use AI to validate if it's a valid PO
      final prompt = '''
Analyze the following text and determine if it is a Purchase Order (PO) document.
Look for: PO number, customer information, line items, quantities, prices, totals.
Respond with only "YES" or "NO".

Text (first 2000 chars):
${pdfText.length > 2000 ? pdfText.substring(0, 2000) : pdfText}
''';
      
      final answer = await _callWithRetry(() async {
        final result = await _model.generateContent([Content.text(prompt)]);
        return result.text?.toUpperCase().trim() ?? '';
      });
      return answer.contains('YES') || answer.contains('VALID');
    } catch (e) {
      // If validation fails, check for basic PO structure
      final lowerText = pdfText.toLowerCase();
      return lowerText.contains('purchase order') || 
             lowerText.contains('po number') ||
             (lowerText.contains('customer') && lowerText.contains('total'));
    }
  }

  /// Build semantic extraction prompt with base64 PDF embedded
  String _buildSemanticExtractionPromptWithBase64(String base64Pdf) {
    // Truncate base64 if too long to avoid token limits (keep first 500KB of base64)
    final truncatedBase64 = base64Pdf.length > 500000 
        ? base64Pdf.substring(0, 500000) 
        : base64Pdf;
    
    return '''
You are processing a Purchase Order PDF document. The PDF file is provided below as base64-encoded binary data with MIME type 'application/pdf'.

CRITICAL: This is NOT corrupted text or metadata. This is a valid PDF file encoded in base64. You MUST:
1. Decode the base64 data to get the PDF binary
2. Process the PDF using your vision/multimodal capabilities (like a human reading a document)
3. Extract ALL readable text and data from the PDF document
4. Look for Purchase Order information visually, not just in raw text

IMPORTANT: The document layout and field labels vary between files. 

Follow these semantic mapping rules:
1. 'totalAmount': Look for values associated with labels like "Grand Total", "Total Amount", "Total AED", "Amount Due", or "Net Total". Extract ONLY the numerical value.
2. 'poNumber': Look for "PO #", "Order No", "Purchase Order Number", "Reference", or "PO-". 
3. 'customerName': Look for "Bill To", "Customer Information", "Customer Name", or the primary entity receiving the order (e.g., 'Delta Engineering Services').
4. 'items': Extract a list of all products/services including description, quantity, and unit price.
5. 'poDate': Look for "Date", "PO Date", "Order Date", "Issue Date", or any date field. Convert to YYYY-MM-DD format.
6. 'expiryDate': Look for "Expiry Date", "Valid Until", "Expires", or similar. Convert to YYYY-MM-DD format or null.
7. 'customerAddress': Extract complete address if available.
8. 'customerEmail': Extract email if available.
9. 'currency': Extract currency code (AED, USD, INR, EUR, etc.) from amount fields.

RETURN DATA STRICTLY IN THIS JSON FORMAT:
{
  "isValid": true,
  "poData": {
    "poNumber": "string or N/A",
    "poDate": "YYYY-MM-DD or null",
    "expiryDate": "YYYY-MM-DD or null",
    "customerName": "string or N/A",
    "customerAddress": "string or null",
    "customerEmail": "string or null",
    "totalAmount": number or 0.0,
    "currency": "string or null",
    "terms": "string or null",
    "notes": "string or null",
    "lineItems": [
      {
        "itemName": "string",
        "itemCode": "string or null",
        "description": "string or null",
        "quantity": number,
        "unit": "string (default: pcs)",
        "unitPrice": number,
        "total": number
      }
    ]
  },
  "summary": "2-3 sentence English summary"
}

CRITICAL RULES:
- If a specific value cannot be found, return "N/A" for strings or 0.0 for numbers. Do NOT return null for required fields.
- Extract whatever information IS available, even if incomplete.
- Handle different document layouts and naming conventions.
- Look for semantic meaning, not just exact label matches.
- If the document is clearly NOT a Purchase Order, set isValid to false and explain in summary.
- The base64 data below is a PDF file - decode it and process it as a PDF document, not as text.

Base64-encoded PDF data (MIME type: application/pdf):
$truncatedBase64
''';
  }

  /// Build semantic extraction prompt for PDF visual processing (inline_data)
  /// This prompt is used when sending PDF bytes directly for multimodal processing
  String _buildSemanticExtractionPromptForPDF() {
    return '''
You are processing a Purchase Order PDF document. The PDF file is provided as binary data with MIME type 'application/pdf'.

CRITICAL: This is a valid PDF file. You MUST:
1. Process the PDF using your vision/multimodal capabilities (like a human reading a document)
2. Extract ALL readable text and data from the PDF document visually
3. Look for Purchase Order information by examining the document layout, not just raw text
4. The document may contain tables, headers, footers, and various formatting - extract data from all sections

IMPORTANT: The document layout and field labels vary between files.

Follow these semantic mapping rules (PRIORITY: If PO fields not found, use Inquiry fields):
1. 'totalAmount': Look for values associated with labels like "Grand Total", "Total Amount", "Total AED", "Amount Due", or "Net Total". Extract ONLY the numerical value.
2. 'poNumber' (PRIMARY): Look for "PO #", "Order No", "Purchase Order Number", "Reference", or "PO-".
   'poNumber' (FALLBACK - Inquiry): If PO Number not found, look for "Inquiry Number", "RFQ Number", "Inquiry No", "RFQ #", "Request for Quotation".
3. 'customerName': Look for "Bill To", "Customer Information", "Customer Name", or the primary entity receiving the order.
4. 'items': Extract a list of all products/services including description, quantity, and unit price from tables or lists.
5. 'poDate' (PRIMARY): Look for "Date", "PO Date", "Order Date", "Issue Date", or any date field. Convert to YYYY-MM-DD format.
   'poDate' (FALLBACK - Inquiry): If PO Date not found, look for "Inquiry Date", "RFQ Date", "Request Date". Convert to YYYY-MM-DD format.
6. 'expiryDate': Look for "Expiry Date", "Valid Until", "Expires", or similar. Convert to YYYY-MM-DD format or null.
7. 'customerAddress': Extract complete address if available.
8. 'customerEmail': Extract email if available.
9. 'currency': Extract currency code (AED, USD, INR, EUR, etc.) from amount fields.

RETURN DATA STRICTLY IN THIS JSON FORMAT:
{
  "isValid": true,
  "poData": {
    "poNumber": "string or N/A",
    "poDate": "YYYY-MM-DD or null",
    "expiryDate": "YYYY-MM-DD or null",
    "customerName": "string or N/A",
    "customerAddress": "string or null",
    "customerEmail": "string or null",
    "totalAmount": number or 0.0,
    "currency": "string or null",
    "terms": "string or null",
    "notes": "string or null",
    "lineItems": [
      {
        "itemName": "string",
        "itemCode": "string or null",
        "description": "string or null",
        "quantity": number,
        "unit": "string (default: pcs)",
        "unitPrice": number,
        "total": number
      }
    ]
  },
  "summary": "2-3 sentence English summary"
}

CRITICAL RULES:
- If a specific value cannot be found, return "N/A" for strings or 0.0 for numbers. Do NOT return null for required fields.
- Extract whatever information IS available, even if incomplete.
- Handle different document layouts and naming conventions.
- Look for semantic meaning, not just exact label matches.
- Process the PDF visually - read it like a human would, identifying labels and values by their position and context.
- If the document is clearly NOT a Purchase Order, set isValid to false and explain in summary.
- The PDF is provided as binary data - process it as a visual document, not as extracted text.
''';
  }

  /// Build semantic extraction prompt for text-based processing
  String _buildSemanticExtractionPrompt() {
    return '''
Extract data from the attached PDF. 
IMPORTANT: The document layout and field labels vary between files. 

Follow these semantic mapping rules:
1. 'totalAmount': Look for values associated with labels like "Grand Total", "Total Amount", "Total AED", "Amount Due", or "Net Total". Extract ONLY the numerical value.
2. 'poNumber': Look for "PO #", "Order No", "Purchase Order Number", "Reference", or "PO-". 
3. 'customerName': Look for "Bill To", "Customer Information", "Customer Name", or the primary entity receiving the order (e.g., 'Delta Engineering Services').
4. 'items': Extract a list of all products/services including description, quantity, and unit price.
5. 'poDate': Look for "Date", "PO Date", "Order Date", "Issue Date", or any date field. Convert to YYYY-MM-DD format.
6. 'expiryDate': Look for "Expiry Date", "Valid Until", "Expires", or similar. Convert to YYYY-MM-DD format or null.
7. 'customerAddress': Extract complete address if available.
8. 'customerEmail': Extract email if available.
9. 'currency': Extract currency code (AED, USD, INR, EUR, etc.) from amount fields.

RETURN DATA STRICTLY IN THIS JSON FORMAT:
{
  "isValid": true,
  "poData": {
    "poNumber": "string or null",
    "poDate": "YYYY-MM-DD or null",
    "expiryDate": "YYYY-MM-DD or null",
    "customerName": "string or null",
    "customerAddress": "string or null",
    "customerEmail": "string or null",
    "totalAmount": number or null,
    "currency": "string or null",
    "terms": "string or null",
    "notes": "string or null",
    "lineItems": [
      {
        "itemName": "string",
        "itemCode": "string or null",
        "description": "string or null",
        "quantity": number,
        "unit": "string (default: pcs)",
        "unitPrice": number,
        "total": number
      }
    ]
  },
  "summary": "2-3 sentence English summary"
}

CRITICAL RULES:
- If a specific value cannot be found, return "N/A" for strings or 0.0 for numbers. Do NOT return null for required fields.
- Extract whatever information IS available, even if incomplete.
- Handle different document layouts and naming conventions.
- Look for semantic meaning, not just exact label matches.
- If the document is clearly NOT a Purchase Order, set isValid to false and explain in summary.
''';
  }

  /// Build multi-format prompt for text-based extraction
  String _buildMultiFormatPrompt(String pdfText) {
    return '''
Extract data from this document. 
1. If it is a Purchase Order, extract the PO Number, Customer Name, Grand Total, and Line Items.
2. Even if the layout or naming is different (like in 'purchase_order_sample.pdf'), look for keywords like 'Total', 'PO #', or 'Bill To'.
3. Return the data STRICTLY as a JSON object with this structure:
{
  "isValid": true,
  "poData": {
    "poNumber": "string or N/A",
    "poDate": "YYYY-MM-DD or null",
    "expiryDate": null,
    "customerName": "string or N/A",
    "customerAddress": "string or null",
    "customerEmail": "string or null",
    "totalAmount": number or 0.0,
    "currency": "string or null",
    "terms": "string or null",
    "notes": null,
    "lineItems": [
      {
        "itemName": "string",
        "itemCode": "string or null",
        "description": null,
        "quantity": number,
        "unit": "pcs",
        "unitPrice": number,
        "total": number
      }
    ]
  },
  "summary": "2-3 sentence English summary"
}
4. If a field is missing, use "N/A" for strings or 0.0 for numbers. Do not return null for required fields.

Document text:
$pdfText
''';
  }

  /// Parse semantic extraction response
  Map<String, dynamic> _parseSemanticResponse(String response) {
    try {
      debugPrint('📥 Raw response length: ${response.length}');
      debugPrint('📥 First 500 chars: ${response.length > 500 ? response.substring(0, 500) : response}');
      
      // Clean JSON response - handle multiple formats
      String cleanJson = response.trim();
      
      // Remove markdown code blocks
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      } else if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();
      
      // Try to extract JSON from text that might contain explanations
      // Look for the first { and last } to extract just the JSON object
      final firstBrace = cleanJson.indexOf('{');
      final lastBrace = cleanJson.lastIndexOf('}');
      if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
        cleanJson = cleanJson.substring(firstBrace, lastBrace + 1);
      }
      
      // Try to fix common JSON issues: single quotes instead of double quotes
      // Only fix property names and simple string values, being careful not to break valid JSON
      // Fix property names with single quotes: 'property': -> "property":
      cleanJson = cleanJson.replaceAllMapped(
        RegExp(r"'(\w+)'\s*:"),
        (match) => '"${match.group(1)}":',
      );
      
      // Fix string values with single quotes (simple case): : 'value' -> : "value"
      // But avoid replacing single quotes that are part of the content
      cleanJson = cleanJson.replaceAllMapped(
        RegExp(r":\s*'([^']*)'(?=\s*[,}\]])"),
        (match) => ': "${match.group(1)}"',
      );
      
      cleanJson = cleanJson.trim();
      
      debugPrint('📥 Cleaned JSON length: ${cleanJson.length}');
      debugPrint('📥 First 500 chars of cleaned: ${cleanJson.length > 500 ? cleanJson.substring(0, 500) : cleanJson}');
      
      // Try to parse JSON
      Map<String, dynamic> jsonData;
      try {
        jsonData = json.decode(cleanJson) as Map<String, dynamic>;
      } catch (jsonError) {
        debugPrint('❌ JSON parse error: $jsonError');
        debugPrint('❌ Problematic JSON (first 1000 chars): ${cleanJson.length > 1000 ? cleanJson.substring(0, 1000) : cleanJson}');
        
        // Try one more time with more aggressive cleaning
        // Remove any text before first { and after last }
        final firstBrace2 = cleanJson.indexOf('{');
        final lastBrace2 = cleanJson.lastIndexOf('}');
        if (firstBrace2 != -1 && lastBrace2 != -1 && lastBrace2 > firstBrace2) {
          final extractedJson = cleanJson.substring(firstBrace2, lastBrace2 + 1);
          debugPrint('🔄 Trying extracted JSON (${extractedJson.length} chars)');
          jsonData = json.decode(extractedJson) as Map<String, dynamic>;
        } else {
          rethrow;
        }
      }
      
      final isValid = jsonData['isValid'] as bool? ?? false;
      final poDataJson = jsonData['poData'] as Map<String, dynamic>?;
      final summary = jsonData['summary'] as String? ?? 'Purchase Order extracted successfully.';
      
      PurchaseOrder? poData;
      if (poDataJson != null && poDataJson.isNotEmpty) {
        try {
          // Convert N/A to null, ensure numbers are not null
          final cleanedPoData = Map<String, dynamic>.from(poDataJson);
          
          // Handle N/A values
          if (cleanedPoData['poNumber'] == 'N/A') cleanedPoData['poNumber'] = null;
          if (cleanedPoData['customerName'] == 'N/A') cleanedPoData['customerName'] = null;
          
          // Ensure numeric fields are not null
          if (cleanedPoData['totalAmount'] == null) cleanedPoData['totalAmount'] = 0.0;
          
          final jsonString = json.encode(cleanedPoData);
          poData = _parseExtractedData(jsonString, '');
          debugPrint('✅ Successfully parsed PO data from semantic extraction');
        } catch (e) {
          debugPrint('Error parsing PO data: $e');
          poData = null;
        }
      }
      
      return {
        'isValid': isValid && poData != null,
        'poData': poData,
        'summary': summary,
      };
    } catch (e) {
      debugPrint('Error parsing semantic response: $e');
      throw Exception('Failed to parse AI response: $e');
    }
  }

  /// Build combined prompt for validation, extraction, and summary
  String _buildCombinedPrompt(String pdfText) {
    return '''
You are an expert AI assistant specialized in processing Purchase Order (PO) documents.

Perform THREE tasks in a single response:

1. VALIDATION: Determine if this is a valid Purchase Order document
   - Be FLEXIBLE and UNDERSTANDING - POs come in many formats
   - A valid PO should have SOME of these elements (not necessarily all):
     * Some form of order number/PO number/order ID (may be labeled as "PO", "Order No", "PO Number", "Order Number", "Reference", etc.)
     * Customer/buyer information (name, company, address, etc.)
     * Items/products being ordered (descriptions, part numbers, SKUs, etc.)
     * Quantities and prices
     * Some form of total amount (grand total, total amount, amount due, etc.)
     * A date (order date, PO date, issue date, etc.)
   - Return true if it appears to be a purchase order, even if some fields are missing
   - Return false ONLY if it's clearly NOT a purchase order (e.g., invoice, receipt, contract, etc.)

2. EXTRACTION: If valid, extract ALL available PO information with 100% accuracy
   - Extract EXACT values as they appear - NO placeholders, NO defaults, NO "N/A", NO "Unknown"
   - Look for information in various formats and labels:
     * PO Number: May be labeled as "PO Number", "PO", "Order No", "Order Number", "Reference", "PO #", "Order ID", etc.
     * Date: May be labeled as "Date", "PO Date", "Order Date", "Issue Date", "Date Issued", etc. → convert to YYYY-MM-DD format
     * Customer Name: May be labeled as "Customer Name", "Customer", "Buyer", "Bill To", "Ship To", "Company Name", etc.
     * Grand Total: May be labeled as "Grand Total", "Total Amount", "Total", "Amount Due", "Total Price", "Sum", etc. → extract numeric value only
   - For line items: Look for tables, lists, or structured data with:
     * Item descriptions, names, or product names
     * Part numbers, SKUs, item codes, or product codes
     * Quantities (may be labeled as "Qty", "Quantity", "QTY", etc.)
     * Unit prices (may be labeled as "Unit Price", "Price", "Rate", "Cost", etc.)
     * Line totals (may be labeled as "Total", "Amount", "Subtotal", etc.)
   - For dates: Convert to YYYY-MM-DD format (handle various date formats)
   - For amounts: Extract ONLY numeric value, remove currency symbols and commas
   - If a field is not found, use null (not "N/A" or "Unknown")
   - Extract whatever information IS available, even if incomplete

3. SUMMARY: Generate a concise 2-3 sentence English summary highlighting key information

Return ONLY valid JSON with this exact structure:
{
  "isValid": true or false,
  "poData": {
    "poNumber": "exact PO number or null",
    "poDate": "date in YYYY-MM-DD format or null",
    "expiryDate": null,
    "customerName": "exact customer name or null",
    "customerAddress": "address or null",
    "customerEmail": "email or null",
    "totalAmount": numeric_value_or_null,
    "currency": "currency code (AED, INR, USD, etc.) or null",
    "terms": "payment terms or null",
    "notes": null,
    "lineItems": [
      {
        "itemName": "description from document",
        "itemCode": "part number or null",
        "description": null,
        "quantity": numeric_value,
        "unit": "pcs",
        "unitPrice": numeric_value,
        "total": numeric_value
      }
    ]
  },
  "summary": "2-3 sentence summary in English"
}

IMPORTANT: 
- Be VERY lenient in validation - if it looks like a purchase order, mark isValid as true
- Extract whatever information you can find, even if some fields are missing
- If the text contains PDF library metadata, technical information, escape sequences (\\x, \\n), or corrupted characters, IGNORE those and look for actual PO content
- Even if text extraction is imperfect or contains PDF technical data, try to extract ANY readable PO information
- Look for patterns like "PO Number:", "Date:", "Customer Name:", "Grand Total:", "Item No", "Description", "Qty", "Unit Price", etc.
- If you see text that looks like it could be a PO number (e.g., "PO-2025-171", "PO12345", etc.), extract it even if the label is unclear
- If you see numbers that look like prices (e.g., "12127.50", "1,127.50"), extract them as amounts
- If you see text that looks like a company name or customer, extract it as customerName
- If isValid is false, poData can be null or empty, but summary should explain why it's invalid
- CRITICAL: Do NOT return null for all fields just because the text is imperfect - extract whatever you can find!

Document text (may contain PDF metadata and technical information - extract only the readable PO content):
$pdfText
''';
  }

  String _buildExtractionPrompt(String pdfText) {
    return '''
You are an expert AI assistant specialized in extracting Purchase Order (PO) information from documents with 100% accuracy.

CRITICAL RULES - READ CAREFULLY:
1. Extract EXACT values as they appear in the document - NO placeholders, NO defaults, NO "N/A", NO "Unknown", NO sample data
2. PRIORITY EXTRACTION RULE: If PO fields are not found, prioritize Inquiry fields:
   - If "PO Number" is not found, look for "Inquiry Number", "RFQ Number", "Inquiry No", "RFQ #", "Request for Quotation"
   - If "PO Date" is not found, look for "Inquiry Date", "RFQ Date", "Request Date"
   - If "Purchase Order" context is missing, check if it's an Inquiry/RFQ document and extract Inquiry fields instead
3. Look for these EXACT patterns in the text:
   - PO Number (PRIMARY): Look for "PO Number:", "PO:", "PO #", "Order No", "Purchase Order Number"
   - PO Number (FALLBACK - Inquiry): If PO Number not found, look for "Inquiry Number:", "RFQ Number:", "Inquiry No:", "RFQ #:", "Request for Quotation"
   - Date (PRIMARY): Look for "PO Date:", "Date:", "Order Date:", "Issue Date:"
   - Date (FALLBACK - Inquiry): If PO Date not found, look for "Inquiry Date:", "RFQ Date:", "Request Date:"
   - Customer Name: Look for "Customer Name:", "Customer:", "Bill To:", "Ship To:"
   - Grand Total: Look for "Grand Total:", "Total Amount:", "Total:", "Amount Due:"
4. For line items: Extract from table with columns: Item No | Description | Part Number | Qty | Unit Price (AED) | Total (AED)
   - Extract ALL rows from the table
   - Use Description column for itemName
   - Use Part Number column for itemCode
   - Use Qty column for quantity
   - Use Unit Price (AED) column for unitPrice
   - Use Total (AED) column for total
5. For dates: Convert to YYYY-MM-DD format
   - "22 November 2025" → "2025-11-22"
   - "November 22, 2025" → "2025-11-22"
6. For amounts: Extract ONLY the numeric value, remove currency symbols and commas
   - "12127.50 AED" → 12127.50
   - "1,127.50" → 1127.50
7. DO NOT use sample data, test data, or placeholder values
8. If a field is not found, use null (not "N/A" or "Unknown")

Return ONLY valid JSON (no markdown, no code blocks, no explanations):
{
  "poNumber": "exact PO number from document",
  "poDate": "date in YYYY-MM-DD format",
  "expiryDate": null,
  "customerName": "exact customer name from document",
  "customerAddress": "address if found, else null",
  "customerEmail": "email if found, else null",
  "totalAmount": numeric_value_only,
  "currency": "currency code (AED, INR, USD, EUR, etc.) if found, else null",
  "terms": "payment terms if found, else null",
  "notes": null,
  "lineItems": [
    {
      "itemName": "description from table",
      "itemCode": "part number from table or null",
      "description": null,
      "quantity": numeric_value,
      "unit": "pcs",
      "unitPrice": numeric_value,
      "total": numeric_valuex
    }
  ]
}

Text to extract from:
$pdfText
''';
  }

  String _buildSummaryPrompt(PurchaseOrder po) {
    return '''
Generate a concise English summary of the following Purchase Order:

PO Number: ${po.poNumber}
Date: ${po.poDate.toString().split(' ')[0]}
Customer: ${po.customerName}
Total Amount: ${po.totalAmount}
Number of Items: ${po.lineItems.length}
Expiry Date: ${po.expiryDate.toString().split(' ')[0]}

Provide a 2-3 sentence summary highlighting key information.
''';
  }

  PurchaseOrder _parseExtractedData(String jsonText, String originalText) {
    try {
      // Clean JSON text (remove markdown code blocks if present)
      String cleanJson = jsonText.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final jsonData = json.decode(cleanJson) as Map<String, dynamic>;
      
      // Extract line items with flexible field matching
      List<LineItem> lineItems = [];
      if (jsonData['lineItems'] != null && jsonData['lineItems'] is List) {
        final itemsList = jsonData['lineItems'] as List<dynamic>;
        for (final item in itemsList) {
          if (item is Map<String, dynamic>) {
            // Handle different field name variations
            final itemName = item['itemName'] ?? 
                           item['name'] ?? 
                           item['description'] ?? 
                           item['item'] ?? 
                           item['product'] ?? '';
            
            final itemCode = item['itemCode'] ?? 
                           item['code'] ?? 
                           item['partNumber'] ?? 
                           item['sku'] ?? 
                           item['partNo'];
            
            final description = item['description'] ?? 
                               item['details'] ?? 
                               item['itemDescription'];
            
            // Extract quantity - handle different field names
            double quantity = 0.0;
            if (item['quantity'] != null) {
              quantity = (item['quantity'] is num) 
                  ? item['quantity'].toDouble() 
                  : (double.tryParse(item['quantity'].toString()) ?? 0.0);
            } else if (item['qty'] != null) {
              quantity = (item['qty'] is num) 
                  ? item['qty'].toDouble() 
                  : (double.tryParse(item['qty'].toString()) ?? 0.0);
            }
            
            final unit = item['unit'] ?? 
                        item['uom'] ?? 
                        item['unitOfMeasure'] ?? 
                        'pcs';
            
            // Extract unit price
            double unitPrice = 0.0;
            if (item['unitPrice'] != null) {
              unitPrice = (item['unitPrice'] is num) 
                  ? item['unitPrice'].toDouble() 
                  : (double.tryParse(item['unitPrice'].toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0);
            } else if (item['price'] != null) {
              unitPrice = (item['price'] is num) 
                  ? item['price'].toDouble() 
                  : (double.tryParse(item['price'].toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0);
            }
            
            // Extract total
            double total = 0.0;
            if (item['total'] != null) {
              total = (item['total'] is num) 
                  ? item['total'].toDouble() 
                  : (double.tryParse(item['total'].toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0);
            } else if (item['lineTotal'] != null) {
              total = (item['lineTotal'] is num) 
                  ? item['lineTotal'].toDouble() 
                  : (double.tryParse(item['lineTotal'].toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0);
            } else if (quantity > 0 && unitPrice > 0) {
              // Calculate if not provided
              total = quantity * unitPrice;
            }
            
            if (itemName.isNotEmpty) {
              lineItems.add(LineItem(
                itemName: itemName,
                itemCode: itemCode,
                description: description,
                quantity: quantity,
                unit: unit,
                unitPrice: unitPrice,
                total: total,
              ));
            }
          }
        }
      }
      
      // If no line items from JSON, try to extract from original text
      if (lineItems.isEmpty) {
        // Try to extract line items from table structure in original text
        final tablePattern = RegExp(
          r'(\d+)\s+(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)',
          caseSensitive: false,
          dotAll: true,
        );
        
        final matches = tablePattern.allMatches(originalText);
        for (final match in matches) {
          final qty = double.tryParse(match.group(3) ?? '0') ?? 0.0;
          final unitPrice = double.tryParse(match.group(4) ?? '0') ?? 0.0;
          final total = double.tryParse(match.group(5) ?? '0') ?? 0.0;
          
          if (qty > 0 && unitPrice > 0) {
            lineItems.add(LineItem(
              itemName: match.group(2)?.trim() ?? '',
              itemCode: null,
              description: null,
              quantity: qty,
              unit: 'pcs',
              unitPrice: unitPrice,
              total: total > 0 ? total : (qty * unitPrice),
            ));
          }
        }
      }

      // Extract PO date with flexible field matching
      String poDateStr = jsonData['poDate'] ?? 
                        jsonData['date'] ?? 
                        jsonData['orderDate'] ?? 
                        jsonData['issueDate'] ?? 
                        '';
      
      // If not found in JSON, try to extract from original text
      if (poDateStr.isEmpty) {
        final datePatterns = [
          RegExp(r'Date[:\s]+([\d\s\w,]+)', caseSensitive: false),
          RegExp(r'Date:\s*([\d\s\w,]+)', caseSensitive: false),
          RegExp(r'PO\s*Date[:\s]+([\d\s\w,]+)', caseSensitive: false),
          RegExp(r'Order\s*Date[:\s]+([\d\s\w,]+)', caseSensitive: false),
          RegExp(r'Issue\s*Date[:\s]+([\d\s\w,]+)', caseSensitive: false),
        ];
        
        for (final pattern in datePatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            final extracted = match.group(1)!.trim();
            // Validate it's a real date, not a placeholder
            if (extracted.isNotEmpty && extracted.length > 5) {
              poDateStr = extracted;
              break;
            }
          }
        }
      }
      
      final poDate = _parseDate(poDateStr);
      
      // Extract expiry date with flexible field matching
      String expiryDateStr = jsonData['expiryDate'] ?? 
                            jsonData['expiry'] ?? 
                            jsonData['validUntil'] ?? 
                            jsonData['expirationDate'] ?? 
                            jsonData['validUntilDate'] ?? 
                            '';
      
      // If not found in JSON, try to extract from original text
      if (expiryDateStr.isEmpty) {
        final expiryPatterns = [
          RegExp(r'Expiry\s*Date[:\s]+([\d\s\w,]+)', caseSensitive: false),
          RegExp(r'Valid\s*Until[:\s]+([\d\s\w,]+)', caseSensitive: false),
          RegExp(r'Expiration[:\s]+([\d\s\w,]+)', caseSensitive: false),
        ];
        
        for (final pattern in expiryPatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            expiryDateStr = match.group(1)!.trim();
            break;
          }
        }
      }
      
      final expiryDate = expiryDateStr.isNotEmpty ? _parseDate(expiryDateStr) : null;
      
      // If expiry date is not found, set it to 30 days from PO date
      final finalExpiryDate = expiryDate ?? poDate.add(const Duration(days: 30));

      String status = 'active';
      if (finalExpiryDate.isBefore(DateTime.now())) {
        status = 'expired';
      } else if (finalExpiryDate.difference(DateTime.now()).inDays <= 7) {
        status = 'expiring_soon';
      }

      // Extract values with better error handling
      final poNumber = jsonData['poNumber']?.toString().trim();
      final customerName = jsonData['customerName']?.toString().trim();
      final totalAmount = jsonData['totalAmount'];
      
      // Validate and extract critical fields with flexible matching
      String finalPONumber = poNumber ?? '';
      if (finalPONumber.isEmpty || finalPONumber == 'N/A' || finalPONumber.toLowerCase() == 'unknown' || finalPONumber.contains('sample') || finalPONumber.contains('test')) {
        // Try multiple patterns for PO number - prioritize exact format from PDF
        final patterns = [
          RegExp(r'PO\s*Number[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'PO\s*Number:\s*([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'PO\s*No[.:\s]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'PO[-\s#]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'Purchase\s*Order[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'Order\s*Number[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
        ];
        
        for (final pattern in patterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            final extracted = match.group(1)!.trim();
            // Validate it's not a placeholder
            if (extracted.isNotEmpty && !extracted.toLowerCase().contains('sample') && !extracted.toLowerCase().contains('test')) {
              finalPONumber = extracted;
              jsonData['poNumber'] = finalPONumber;
              break;
            }
          }
        }
      }
      
      String finalCustomerName = customerName ?? '';
      if (finalCustomerName.isEmpty || finalCustomerName == 'Unknown' || finalCustomerName.toLowerCase() == 'n/a' || finalCustomerName.toLowerCase().contains('sample') || finalCustomerName.toLowerCase().contains('test') || finalCustomerName.toLowerCase().contains('acme')) {
        // Try multiple patterns for customer name - prioritize exact format from PDF
        final patterns = [
          RegExp(r'Customer\s*Name[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Customer\s*Name:\s*(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Customer[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Company[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Client[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
        ];
        
        for (final pattern in patterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            final extracted = match.group(1)!.trim();
            // Clean up - remove extra whitespace and validate it's not a placeholder
            finalCustomerName = extracted.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (finalCustomerName.isNotEmpty && !finalCustomerName.toLowerCase().contains('sample') && !finalCustomerName.toLowerCase().contains('test') && !finalCustomerName.toLowerCase().contains('acme')) {
              jsonData['customerName'] = finalCustomerName;
              break;
            }
          }
        }
      }
      
      // Extract currency first
      String? extractedCurrency = jsonData['currency']?.toString().trim().toUpperCase();
      if (extractedCurrency == null || extractedCurrency.isEmpty || extractedCurrency == 'NULL') {
        // Try to extract currency from original text
        final currencyPatterns = [
          RegExp(r'Grand\s*Total[:\s]+[\d,]+\.?\d*\s*([A-Z]{3})', caseSensitive: false),
          RegExp(r'Total[:\s]+[\d,]+\.?\d*\s*([A-Z]{3})', caseSensitive: false),
          RegExp(r'Unit\s*Price\s*\(([A-Z]{3})\)', caseSensitive: false),
          RegExp(r'Total\s*\(([A-Z]{3})\)', caseSensitive: false),
          RegExp(r'([A-Z]{3})\s*\d+\.?\d*', caseSensitive: false), // Pattern like "AED 12127.50"
        ];
        
        for (final pattern in currencyPatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            extractedCurrency = match.group(1)!.trim().toUpperCase();
            // Validate it's a known currency code
            if (['AED', 'INR', 'USD', 'EUR', 'GBP', 'SAR', 'QAR', 'KWD', 'OMR', 'BHD'].contains(extractedCurrency)) {
              break;
            }
          }
        }
        
        // Check for currency symbols and text variations
        if (extractedCurrency == null || extractedCurrency.isEmpty) {
          final upperText = originalText.toUpperCase();
          if (upperText.contains('₹') || upperText.contains('INR') || upperText.contains('RUPEE') || upperText.contains('RUPEES')) {
            extractedCurrency = 'INR';
          } else if (upperText.contains('AED') || upperText.contains('DIRHAM') || upperText.contains('DIRHAMS') || upperText.contains('UAE')) {
            extractedCurrency = 'AED';
          } else if (upperText.contains('\$') || upperText.contains('USD') || upperText.contains('DOLLAR') || upperText.contains('DOLLARS')) {
            extractedCurrency = 'USD';
          } else if (upperText.contains('€') || upperText.contains('EUR') || upperText.contains('EURO') || upperText.contains('EUROS')) {
            extractedCurrency = 'EUR';
          } else if (upperText.contains('£') || upperText.contains('GBP') || upperText.contains('POUND') || upperText.contains('POUNDS')) {
            extractedCurrency = 'GBP';
          } else if (upperText.contains('SAR') || upperText.contains('RIYAL') || upperText.contains('RIYALS')) {
            extractedCurrency = 'SAR';
          } else if (upperText.contains('QAR')) {
            extractedCurrency = 'QAR';
          } else if (upperText.contains('KWD') || upperText.contains('DINAR') || upperText.contains('DINARS')) {
            extractedCurrency = 'KWD';
          } else if (upperText.contains('OMR')) {
            extractedCurrency = 'OMR';
          } else if (upperText.contains('BHD')) {
            extractedCurrency = 'BHD';
          }
        }
      }
      
      // Extract total amount - handle different formats and field names
      double finalTotalAmount = 0.0;
      if (totalAmount != null) {
        if (totalAmount is num) {
          finalTotalAmount = totalAmount.toDouble();
        } else if (totalAmount is String) {
          // Remove currency symbols and commas
          final cleanAmount = totalAmount.replaceAll(RegExp(r'[^\d.]'), '');
          finalTotalAmount = double.tryParse(cleanAmount) ?? 0.0;
        }
      }
      
      // If total is 0 or missing, try to extract from original text with multiple patterns
      if (finalTotalAmount == 0.0) {
        final totalPatterns = [
          RegExp(r'Grand\s*Total[:\s]+([\d,]+\.?\d*)\s*(?:AED|USD|INR|₹|\$)?', caseSensitive: false),
          RegExp(r'Grand\s*Total:\s*([\d,]+\.?\d*)\s*(?:AED|USD|INR|₹|\$)?', caseSensitive: false),
          RegExp(r'Total\s*Amount[:\s]+([\d,]+\.?\d*)\s*(?:AED|USD|INR|₹|\$)?', caseSensitive: false),
          RegExp(r'Final\s*Total[:\s]+([\d,]+\.?\d*)\s*(?:AED|USD|INR|₹|\$)?', caseSensitive: false),
          RegExp(r'Amount\s*Due[:\s]+([\d,]+\.?\d*)\s*(?:AED|USD|INR|₹|\$)?', caseSensitive: false),
          RegExp(r'Total[:\s]+([\d,]+\.?\d*)\s*(?:AED|USD|INR|₹|\$)', caseSensitive: false),
        ];
        
        for (final pattern in totalPatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            final cleanAmount = match.group(1)!.replaceAll(',', '').trim();
            final parsed = double.tryParse(cleanAmount) ?? 0.0;
            if (parsed > 0) {
              finalTotalAmount = parsed;
              break;
            }
          }
        }
      }

      // Final validation - reject sample/test data
      final finalPONumberValid = finalPONumber.isNotEmpty && 
                                 finalPONumber != 'N/A' && 
                                 !finalPONumber.toLowerCase().contains('sample') &&
                                 !finalPONumber.toLowerCase().contains('test');
      
      final finalCustomerNameValid = finalCustomerName.isNotEmpty && 
                                     finalCustomerName != 'Unknown' && 
                                     !finalCustomerName.toLowerCase().contains('sample') &&
                                     !finalCustomerName.toLowerCase().contains('test') &&
                                     !finalCustomerName.toLowerCase().contains('acme');
      
      return PurchaseOrder(
        poNumber: finalPONumberValid ? finalPONumber : (jsonData['poNumber']?.toString().trim() ?? 'N/A'),
        poDate: poDate,
        expiryDate: finalExpiryDate,
        customerName: finalCustomerNameValid ? finalCustomerName : (jsonData['customerName']?.toString().trim() ?? 'Unknown'),
        customerAddress: jsonData['customerAddress']?.toString(),
        customerEmail: jsonData['customerEmail']?.toString(),
        totalAmount: finalTotalAmount,
        currency: extractedCurrency,
        terms: jsonData['terms']?.toString(),
        notes: jsonData['notes']?.toString(),
        lineItems: lineItems,
        createdAt: DateTime.now(),
        status: status,
      );
    } catch (e) {
      throw Exception('Failed to parse extracted data: $e');
    }
  }

  DateTime _parseDate(String dateString) {
    try {
      if (dateString.isEmpty) {
        return DateTime.now();
      }
      
      // Clean the date string
      String cleanDate = dateString.trim();
      
      // Handle formats like "22 November 2025" or "November 22, 2025"
      final monthNames = {
        'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
        'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      
      // Try to parse "DD Month YYYY" format
      final monthPattern = RegExp(r'(\d{1,2})\s+([a-z]+)\s+(\d{4})', caseSensitive: false);
      final monthMatch = monthPattern.firstMatch(cleanDate);
      if (monthMatch != null) {
        final day = int.parse(monthMatch.group(1)!);
        final monthName = monthMatch.group(2)!.toLowerCase();
        final year = int.parse(monthMatch.group(3)!);
        final month = monthNames[monthName];
        if (month != null) {
          return DateTime(year, month, day);
        }
      }
      
      // Try "Month DD, YYYY" format
      final monthPattern2 = RegExp(r'([a-z]+)\s+(\d{1,2}),?\s+(\d{4})', caseSensitive: false);
      final monthMatch2 = monthPattern2.firstMatch(cleanDate);
      if (monthMatch2 != null) {
        final monthName = monthMatch2.group(1)!.toLowerCase();
        final day = int.parse(monthMatch2.group(2)!);
        final year = int.parse(monthMatch2.group(3)!);
        final month = monthNames[monthName];
        if (month != null) {
          return DateTime(year, month, day);
        }
      }
      
      // Try standard formats: YYYY-MM-DD, DD-MM-YYYY, MM/DD/YYYY, etc.
      final parts = cleanDate.split(RegExp(r'[-/\s]'));
      if (parts.length == 3) {
        // Try YYYY-MM-DD first
        if (parts[0].length == 4) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
        // Try DD-MM-YYYY or MM-DD-YYYY
        else {
          final first = int.parse(parts[0]);
          final second = int.parse(parts[1]);
          final year = int.parse(parts[2]);
          // Assume DD-MM-YYYY if first part > 12, otherwise MM-DD-YYYY
          if (first > 12) {
            return DateTime(year, second, first);
          } else {
            return DateTime(year, first, second);
          }
        }
      }
      
      // Fallback to current date
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  // ========== CUSTOMER INQUIRY EXTRACTION ==========
  /// Extract Customer Inquiry data directly from PDF bytes (PRIMARY METHOD)
  /// Uses inline_data format for true multimodal processing - reads PDF visually
  Future<CustomerInquiry> extractInquiryFromPDFBytes(Uint8List pdfBytes, String fileName) async {
    try {
      debugPrint('=== Direct Multimodal Inquiry Extraction with inline_data ===');
      debugPrint('PDF file: $fileName, Size: ${pdfBytes.length} bytes');

      // Build prompt for Purchase Requisition/Inquiry extraction
      final prompt = '''
You are processing a Customer Inquiry/Purchase Requisition PDF document. The PDF file is provided as binary data with MIME type 'application/pdf'.

CRITICAL: Process the PDF using your vision/multimodal capabilities (like a human reading a document visually).

This document may be in "Purchase Requisition" format with a table containing these columns:
- Purchase Requisition (use this as inquiryNumber)
- Item of Requisition
- Material (use this as itemCode)
- Short Text (use this as itemName)
- VPN
- Class (use this as classCode)
- Quantity Requested (use this as quantity)
- Unit of Measure (use this as unit)
- Plant (use this as plant, and also extract as customerName if customer name is not found elsewhere)

EXTRACTION RULES:
1. If document has "Purchase Requisition" table format:
   - Extract "Purchase Requisition" number as inquiryNumber
   - Extract "Plant" as customerName (if customer name not found elsewhere)
   - For each row in the table, extract:
     * "Short Text" → itemName
     * "Material" → itemCode
     * "Quantity Requested" → quantity
     * "Unit of Measure" → unit
     * "Class" → classCode
     * "Plant" → plant

2. If document is in standard Inquiry/RFQ format:
   - Look for Inquiry/RFQ Number (RFQ#, Inquiry No, Request for Quotation, etc.)
   - Look for Inquiry Date
   - Look for Customer Name and contact details
   - Extract items with Material Code, Description, Quantity, Unit of Measure, Manufacturer Part, Class, Plant

RETURN DATA STRICTLY IN THIS JSON FORMAT:
{
  "inquiryNumber": "Purchase Requisition number or RFQ number or inquiry reference",
  "inquiryDate": "YYYY-MM-DD (use current date if not found)",
  "customerName": "Plant name or Customer name from document",
  "customerAddress": "Address if available",
  "customerEmail": "Email if available",
  "customerPhone": "Phone if available",
  "notes": "Any notes or requirements",
  "items": [
    {
      "itemName": "Short Text or Item description",
      "itemCode": "Material code",
      "description": "Full description (can be same as itemName)",
      "quantity": 2.0,
      "unit": "EA or Unit of Measure",
      "manufacturerPart": "Part number if available",
      "classCode": "Class code if available",
      "plant": "Plant name if available"
    }
  ]
}

CRITICAL RULES:
- Process the PDF visually - read it like a human would, identifying labels and values by their position and context
- Extract ALL available information from the table/document
- If a field is not found, use null for optional fields or reasonable defaults
- The PDF is provided as binary data - process it as a visual document, not as extracted text
''';

      // Encode PDF bytes to base64
      final base64Pdf = base64Encode(pdfBytes);

      // Build the request body with inline_data (multimodal processing)
      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'inline_data': {
                  'mime_type': 'application/pdf',
                  'data': base64Pdf,
                }
              },
              {
                'text': prompt,
              }
            ]
          }
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'maxOutputTokens': 2048,
        }
      };

      debugPrint('📤 Sending PDF using inline_data (visual processing)');
      debugPrint('📤 PDF size: ${pdfBytes.length} bytes, Base64 size: ${base64Pdf.length} chars');

      // Make HTTP request directly to Gemini API
      final response = await _callWithRetry(() async {
        debugPrint('📡 Making HTTP request to Gemini API with inline_data...');
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/${AppConstants.geminiModel}:generateContent?key=${AppConstants.geminiApiKey}',
        );

        final httpResponse = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        ).timeout(const Duration(minutes: 2));

        if (httpResponse.statusCode != 200) {
          throw Exception('API error: ${httpResponse.statusCode} - ${httpResponse.body}');
        }

        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        final candidates = responseJson['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No candidates in response');
        }

        final firstCandidate = candidates[0] as Map<String, dynamic>;
        final content = firstCandidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw Exception('No parts in response');
        }

        final textPart = parts[0] as Map<String, dynamic>?;
        final responseText = textPart?['text'] as String? ?? '';
        debugPrint('✅ Received response from API: ${responseText.length} characters');
        return responseText;
      });

      if (response.isEmpty) {
        throw Exception('AI returned empty response');
      }

      // Parse JSON response
      String cleanJson = response.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final jsonData = json.decode(cleanJson) as Map<String, dynamic>;

      // Parse items
      final items = (jsonData['items'] as List? ?? []).map((item) {
        return InquiryItem(
          itemName: item['itemName'] as String? ?? 'Unknown Item',
          itemCode: item['itemCode'] as String?,
          description: item['description'] as String?,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: item['unit'] as String? ?? 'EA',
          manufacturerPart: item['manufacturerPart'] as String?,
          classCode: item['classCode'] as String?,
          plant: item['plant'] as String?,
        );
      }).toList();

      // Parse inquiry date
      DateTime inquiryDate;
      try {
        final dateStr = jsonData['inquiryDate'] as String?;
        if (dateStr != null && dateStr.isNotEmpty) {
          inquiryDate = DateTime.parse(dateStr);
        } else {
          inquiryDate = DateTime.now();
        }
      } catch (e) {
        inquiryDate = DateTime.now();
      }

      final inquiry = CustomerInquiry(
        inquiryNumber: jsonData['inquiryNumber'] as String? ?? 'INQ-${DateTime.now().millisecondsSinceEpoch}',
        inquiryDate: inquiryDate,
        customerName: jsonData['customerName'] as String? ?? 'Unknown Customer',
        customerAddress: jsonData['customerAddress'] as String?,
        customerEmail: jsonData['customerEmail'] as String?,
        customerPhone: jsonData['customerPhone'] as String?,
        notes: jsonData['notes'] as String?,
        items: items,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      debugPrint('✅ Successfully extracted inquiry: ${inquiry.inquiryNumber} with ${items.length} items');
      return inquiry;
    } catch (e) {
      debugPrint('❌ Error in extractInquiryFromPDFBytes: $e');
      // Fallback to text-based extraction
      debugPrint('🔄 Falling back to text-based extraction...');
      try {
        final pdfText = await extractTextFromPDFBytes(pdfBytes, fileName);
        return await extractInquiryData(pdfText);
      } catch (fallbackError) {
        debugPrint('❌ Fallback extraction also failed: $fallbackError');
        rethrow;
      }
    }
  }

  /// Extract Customer Inquiry data from PDF text (FALLBACK METHOD)
  Future<CustomerInquiry> extractInquiryData(String pdfText) async {
    try {
      if (pdfText.isEmpty || pdfText.length < 50) {
        throw Exception('PDF text extraction failed. Please ensure the PDF contains readable text.');
      }

      // Sanitize PDF text before processing
      final sanitizedText = sanitizePdfText(pdfText);

      final prompt = '''
Extract all information from this Customer Inquiry/Purchase Requisition document and return it as JSON.

CRITICAL: This document may be in "Purchase Requisition" format with a table containing the following columns:
- Purchase Requisition (use this as inquiryNumber)
- Item of Requisition
- Material (use this as itemCode)
- Short Text (use this as itemName)
- VPN
- Class (use this as classCode)
- Quantity Requested (use this as quantity)
- Unit of Measure (use this as unit)
- Plant (use this as plant, and also extract as customerName if customer name is not found elsewhere)

EXTRACTION RULES:
1. If document has "Purchase Requisition" table format:
   - Extract "Purchase Requisition" number as inquiryNumber
   - Extract "Plant" as customerName (if customer name not found elsewhere)
   - For each row in the table, extract:
     * "Short Text" → itemName
     * "Material" → itemCode
     * "Quantity Requested" → quantity
     * "Unit of Measure" → unit
     * "Class" → classCode
     * "Plant" → plant

2. If document is in standard Inquiry/RFQ format:
   - Look for Inquiry/RFQ Number (RFQ#, Inquiry No, Request for Quotation, etc.)
   - Look for Inquiry Date
   - Look for Customer Name and contact details
   - Extract items with Material Code, Description, Quantity, Unit of Measure, Manufacturer Part, Class, Plant

3. If document contains Purchase Order (PO) fields instead:
   - Extract PO fields first (PO Number, PO Date, Customer Name, etc.)
   - Then check if Inquiry fields are also present

Return JSON in this format:
{
  "inquiryNumber": "Purchase Requisition number or RFQ number or inquiry reference",
  "inquiryDate": "YYYY-MM-DD (use current date if not found)",
  "customerName": "Plant name or Customer name from document",
  "customerAddress": "Address if available",
  "customerEmail": "Email if available",
  "customerPhone": "Phone if available",
  "notes": "Any notes or requirements",
  "items": [
    {
      "itemName": "Short Text or Item description",
      "itemCode": "Material code",
      "description": "Full description (can be same as itemName)",
      "quantity": 2.0,
      "unit": "EA or Unit of Measure",
      "manufacturerPart": "Part number if available",
      "classCode": "Class code if available",
      "plant": "Plant name if available"
    }
  ]
}

PDF Text:
$sanitizedText
''';

      final extractedText = await _callWithRetry(() async {
        final result = await _jsonModel.generateContent([Content.text(prompt)])
            .timeout(const Duration(minutes: 2));
        return result.text ?? '';
      });

      if (extractedText.isEmpty) {
        throw Exception('AI did not return any data. Please try again.');
      }

      // Parse JSON response
      String cleanJson = extractedText.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final jsonData = json.decode(cleanJson) as Map<String, dynamic>;

      final items = (jsonData['items'] as List? ?? []).map((item) {
        return InquiryItem(
          itemName: item['itemName'] as String? ?? 'Unknown Item',
          itemCode: item['itemCode'] as String?,
          description: item['description'] as String?,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: item['unit'] as String? ?? 'EA',
          manufacturerPart: item['manufacturerPart'] as String?,
          classCode: item['classCode'] as String?,
          plant: item['plant'] as String?,
        );
      }).toList();

      return CustomerInquiry(
        inquiryNumber: jsonData['inquiryNumber'] as String? ?? 'INQ-${DateTime.now().millisecondsSinceEpoch}',
        inquiryDate: _parseDate(jsonData['inquiryDate'] as String? ?? ''),
        customerName: jsonData['customerName'] as String? ?? 'Unknown Customer',
        customerAddress: jsonData['customerAddress'] as String?,
        customerEmail: jsonData['customerEmail'] as String?,
        customerPhone: jsonData['customerPhone'] as String?,
        notes: jsonData['notes'] as String?,
        items: items,
        status: 'pending',
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('ERROR in extractInquiryData: $e');
      throw Exception('Failed to extract inquiry data: $e');
    }
  }

  // ========== QUOTATION EXTRACTION ==========
  /// Extract Quotation data from PDF text
  Future<Quotation> extractQuotationData(String pdfText) async {
    try {
      if (pdfText.isEmpty || pdfText.length < 50) {
        throw Exception('PDF text extraction failed. Please ensure the PDF contains readable text.');
      }

      final prompt = '''
Extract all information from this Quotation document and return it as JSON.

Look for:
- Quotation Number (Qtn No, Quote No, Quotation #, etc.)
- Quotation Date
- Validity Date
- Customer Name and contact details
- Items with prices (Description, Material Code, Quantity, Unit Price, Total, Manufacturer Part)
- Total Amount
- Currency
- Terms and Conditions
- Notes

Return JSON in this format:
{
  "quotationNumber": "Quotation number",
  "quotationDate": "YYYY-MM-DD",
  "validityDate": "YYYY-MM-DD",
  "customerName": "Customer name",
  "customerAddress": "Address if available",
  "customerEmail": "Email if available",
  "customerPhone": "Phone if available",
  "totalAmount": 37.00,
  "currency": "AED",
  "terms": "Terms and conditions",
  "notes": "Any notes",
  "items": [
    {
      "itemName": "Item description",
      "itemCode": "Material code",
      "description": "Full description",
      "quantity": 2.0,
      "unit": "EA",
      "unitPrice": 18.50,
      "total": 37.00,
      "manufacturerPart": "Part number if available"
    }
  ]
}

PDF Text:
$pdfText
''';

      final extractedText = await _callWithRetry(() async {
        final result = await _jsonModel.generateContent([Content.text(prompt)])
            .timeout(const Duration(minutes: 2));
        return result.text ?? '';
      });

      if (extractedText.isEmpty) {
        throw Exception('AI did not return any data. Please try again.');
      }

      // Parse JSON response
      String cleanJson = extractedText.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final jsonData = json.decode(cleanJson) as Map<String, dynamic>;

      final items = (jsonData['items'] as List? ?? []).map((item) {
        return QuotationItem(
          itemName: item['itemName'] as String? ?? 'Unknown Item',
          itemCode: item['itemCode'] as String?,
          description: item['description'] as String?,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: item['unit'] as String? ?? 'EA',
          unitPrice: (item['unitPrice'] as num?)?.toDouble() ?? 0.0,
          total: (item['total'] as num?)?.toDouble() ?? 0.0,
          manufacturerPart: item['manufacturerPart'] as String?,
        );
      }).toList();

      final calculatedTotal = items.fold<double>(0.0, (sum, item) => sum + item.total);
      final totalAmount = (jsonData['totalAmount'] as num?)?.toDouble() ?? calculatedTotal;

      return Quotation(
        quotationNumber: jsonData['quotationNumber'] as String? ?? 'QTN-${DateTime.now().millisecondsSinceEpoch}',
        quotationDate: _parseDate(jsonData['quotationDate'] as String? ?? ''),
        validityDate: _parseDate(jsonData['validityDate'] as String? ?? DateTime.now().add(const Duration(days: 30)).toIso8601String()),
        customerName: jsonData['customerName'] as String? ?? 'Unknown Customer',
        customerAddress: jsonData['customerAddress'] as String?,
        customerEmail: jsonData['customerEmail'] as String?,
        customerPhone: jsonData['customerPhone'] as String?,
        items: items,
        totalAmount: totalAmount,
        currency: jsonData['currency'] as String? ?? 'AED',
        terms: jsonData['terms'] as String?,
        notes: jsonData['notes'] as String?,
        status: 'draft',
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('ERROR in extractQuotationData: $e');
      throw Exception('Failed to extract quotation data: $e');
    }
  }

  /// Generate quotation PDF content as HTML (can be converted to PDF)
  Future<String> generateQuotationPDFContent(Quotation quotation) async {
    try {
      final itemsHtml = quotation.items.map((item) {
        return '''
          <tr>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;">${item.itemName}</td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd;">${item.itemCode ?? '-'}</td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd; text-align: right;">${item.quantity} ${item.unit}</td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd; text-align: right;">${quotation.currency} ${item.unitPrice.toStringAsFixed(2)}</td>
            <td style="padding: 8px; border-bottom: 1px solid #ddd; text-align: right;">${quotation.currency} ${item.total.toStringAsFixed(2)}</td>
          </tr>
        ''';
      }).join('');

      final htmlContent = '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Quotation ${quotation.quotationNumber}</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 40px; color: #333; }
            .header { border-bottom: 3px solid #4CAF50; padding-bottom: 20px; margin-bottom: 30px; }
            .header h1 { color: #4CAF50; margin: 0; }
            .info-section { margin-bottom: 30px; }
            .info-row { margin: 10px 0; }
            table { width: 100%; border-collapse: collapse; margin: 20px 0; }
            th { background-color: #4CAF50; color: white; padding: 12px; text-align: left; }
            td { padding: 8px; }
            .total-section { text-align: right; margin-top: 20px; font-size: 18px; font-weight: bold; }
            .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }
          </style>
        </head>
        <body>
          <div class="header">
            <h1>QUOTATION</h1>
            <div class="info-row"><strong>Quotation Number:</strong> ${quotation.quotationNumber}</div>
            <div class="info-row"><strong>Date:</strong> ${quotation.quotationDate.toString().split(' ')[0]}</div>
            <div class="info-row"><strong>Valid Until:</strong> ${quotation.validityDate.toString().split(' ')[0]}</div>
          </div>
          
          <div class="info-section">
            <h3>Customer Information</h3>
            <div class="info-row"><strong>Name:</strong> ${quotation.customerName}</div>
            ${quotation.customerAddress != null ? '<div class="info-row"><strong>Address:</strong> ${quotation.customerAddress}</div>' : ''}
            ${quotation.customerEmail != null ? '<div class="info-row"><strong>Email:</strong> ${quotation.customerEmail}</div>' : ''}
            ${quotation.customerPhone != null ? '<div class="info-row"><strong>Phone:</strong> ${quotation.customerPhone}</div>' : ''}
          </div>
          
          <table>
            <thead>
              <tr>
                <th>Item Name</th>
                <th>Item Code</th>
                <th style="text-align: right;">Quantity</th>
                <th style="text-align: right;">Unit Price</th>
                <th style="text-align: right;">Total</th>
              </tr>
            </thead>
            <tbody>
              $itemsHtml
            </tbody>
          </table>
          
          <div class="total-section">
            <div>Grand Total: ${quotation.currency} ${quotation.totalAmount.toStringAsFixed(2)}</div>
          </div>
          
          ${quotation.terms != null ? '<div class="info-section"><h3>Terms & Conditions</h3><p>${quotation.terms}</p></div>' : ''}
          ${quotation.notes != null ? '<div class="info-section"><h3>Notes</h3><p>${quotation.notes}</p></div>' : ''}
          
          <div class="footer">
            <p>This is a computer-generated quotation. For any queries, please contact us.</p>
          </div>
        </body>
        </html>
      ''';

      return htmlContent;
    } catch (e) {
      debugPrint('Error generating quotation PDF content: $e');
      rethrow;
    }
  }
}

