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
import 'catalog_service.dart';

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
You are an expert data extractor. The PDF file is provided as binary data with MIME type 'application/pdf'.

Process the PDF using your vision/multimodal capabilities (like a human reading a document) and extract data dynamically from any PO layout.

DYNAMIC FIELD EXTRACTION - Identify and extract the following values from the provided PDF:

1. poNumber: Find the unique identifier for the Purchase Order. Look for patterns like:
   - "PO No.", "PO Number", "PO #", "Order #", "Order No", "Reference", "PO-", "Purchase Order Number"
   - Extract the exact value as it appears (e.g., "9500363555", "PO-2025-001")

2. totalValue (totalAmount): Find the final grand total amount. 
   - Look for labels like "Grand Total", "Total Amount", "Total AED", "Amount Due", "Net Total", "Final Total"
   - IGNORE sub-totals, line item totals, or intermediate calculations
   - Extract ONLY the absolute final amount including all taxes and fees
   - Extract the numeric value only (remove currency symbols and commas)

3. customerName: Identify the buyer or company name.
   - Look for "Bill To", "Customer Information", "Customer Name", "Buyer", "Company Name"
   - Extract the primary entity receiving the order (e.g., "Almarai", "Delta Engineering Services")
   - This is usually the company name prominently displayed

4. lineItems: Extract all products/services from tables or item lists.
   - For each item, extract: description/itemName, quantity, unit, and unitPrice
   - Include item codes/part numbers if available
   - Extract from any table format or list structure

5. poDate: Find the order date and convert to YYYY-MM-DD format.
   - Look for "Date", "PO Date", "Order Date", "Issue Date", "Date Issued"

6. Other fields (optional): expiryDate, customerAddress, customerEmail, currency, terms, notes

CRITICAL: Return ONLY a raw JSON object. Do not include any conversational text, backticks, or markdown formatting.

RETURN DATA STRICTLY IN THIS JSON FORMAT (NO MARKDOWN, NO CODE BLOCKS, NO EXPLANATIONS):
{
  "isValid": true,
  "poData": {
    "poNumber": "extracted PO number or null",
    "poDate": "YYYY-MM-DD or null",
    "expiryDate": "YYYY-MM-DD or null",
    "customerName": "extracted customer name or null",
    "customerAddress": "address or null",
    "customerEmail": "email or null",
    "totalAmount": numeric_value_or_null,
    "currency": "currency code or null",
    "terms": "payment terms or null",
    "notes": "notes or null",
    "lineItems": [
      {
        "itemName": "product description",
        "itemCode": "part number or null",
        "description": "additional description or null",
        "quantity": numeric_value,
        "unit": "pcs or other unit",
        "unitPrice": numeric_value,
        "total": numeric_value
      }
    ]
  },
  "summary": "2-3 sentence English summary"
}

CRITICAL RULES:
- Return ONLY the JSON object. No markdown code blocks, no explanations, no conversational text.
- Extract values dynamically - adapt to different document layouts and naming conventions.
- If a value cannot be found, return null for optional fields or 0.0 for numbers.
- Process the PDF visually - read it like a human would, identifying labels and values by position and context.
- The PDF is provided as binary data - process it as a visual document, not as extracted text.
''';
  }


  /// Build multi-format prompt for text-based extraction
  String _buildMultiFormatPrompt(String pdfText) {
    return '''
Extract data from this document. 
1. If it is a Purchase Order, extract the PO Number, Customer Name, Grand Total, and Line Items.
2. Even if the layout or naming is different (like in 'purchase_order_sample.pdf'), look for keywords like 'Total', 'PO #', or 'Bill To'.

CRITICAL: Return ONLY a raw JSON object. Do not include any conversational text, backticks, or markdown formatting.

3. Return the data STRICTLY as a JSON object with this structure (NO MARKDOWN, NO CODE BLOCKS):
{
  "isValid": true,
  "poData": {
    "poNumber": "string or null",
    "poDate": "YYYY-MM-DD or null",
    "expiryDate": null,
    "customerName": "string or null",
    "customerAddress": "string or null",
    "customerEmail": "string or null",
    "totalAmount": number or null,
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
4. If a field is missing, use null for optional fields or 0.0 for numbers. Handle null values gracefully.

Document text:
$pdfText
''';
  }

  /// Parse semantic extraction response
  /// Comprehensive JSON repair function that handles all edge cases
  String _repairJson(String jsonString) {
    String result = jsonString;
    
    // Step 1: Remove markdown code blocks - be very thorough
    result = result.trim();
    
    // Remove all markdown code block markers (```json, ```, etc.)
    result = result.replaceAll(RegExp(r'^```json\s*', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^```\s*', multiLine: true), '');
    result = result.replaceAll(RegExp(r'```json\s*$', multiLine: true), '');
    result = result.replaceAll(RegExp(r'```\s*$', multiLine: true), '');
    
    // Also handle inline markdown
    result = result.replaceAll(RegExp(r'```json'), '');
    result = result.replaceAll(RegExp(r'```'), '');
    
    result = result.trim();
    
    // Step 2: Extract JSON object (between first { and last })
    final firstBrace = result.indexOf('{');
    final lastBrace = result.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      result = result.substring(firstBrace, lastBrace + 1);
    }
    
    // Step 3: Remove comments
    result = result.replaceAll(RegExp(r'//.*'), '');
    result = result.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    
    // Step 4: FIX ALL UNQUOTED PROPERTY NAMES - Most aggressive approach
    // This regex catches property names that are NOT inside strings
    // It looks for: { or , or start of line, then whitespace, then word, then : 
    // But we need to be careful not to match inside string values
    
    // First, let's use a more sophisticated approach:
    // Process the JSON and quote ALL property names that aren't already quoted
    final buffer = StringBuffer();
    bool inString = false;
    bool escapeNext = false;
    int i = 0;
    
    while (i < result.length) {
      final char = result[i];
      
      // Handle escape sequences
      if (escapeNext) {
        buffer.write(char);
        escapeNext = false;
        i++;
        continue;
      }
      
      if (char == '\\') {
        buffer.write(char);
        escapeNext = true;
        i++;
        continue;
      }
      
      // Track string boundaries
      if (char == '"') {
        inString = !inString;
        buffer.write(char);
        i++;
        continue;
      }
      
      // Outside strings - look for unquoted property names
      if (!inString) {
        // Check if we're at the start of a potential property name
        // Look ahead to see if we have: word + optional whitespace + colon
        final remaining = result.substring(i);
        final propMatch = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:').firstMatch(remaining);
        
        if (propMatch != null) {
          final propName = propMatch.group(1)!;
          final beforeMatch = buffer.toString();
          
          // Check if we're in a valid position for a property name
          // Valid positions: after {, after ,, or at start of line (with whitespace before)
          final lastFewChars = beforeMatch.length > 10 
              ? beforeMatch.substring(beforeMatch.length - 10) 
              : beforeMatch;
          final isValidPosition = beforeMatch.isEmpty || 
                                  beforeMatch.endsWith('{') || 
                                  beforeMatch.endsWith(',') ||
                                  beforeMatch.endsWith('\n') ||
                                  beforeMatch.endsWith('[') ||
                                  RegExp(r'[,\{\[\s]$').hasMatch(beforeMatch);
          
          // Check if property name is already quoted - be more thorough
          final isAlreadyQuoted = lastFewChars.endsWith('"') || 
                                  lastFewChars.contains('"$propName"') ||
                                  beforeMatch.endsWith('"');
          
          if (isValidPosition && !isAlreadyQuoted) {
            // Add quotes around property name
            buffer.write('"$propName":');
            i += propMatch.end; // Skip the property name and colon
            continue;
          }
        }
      }
      
      // Write the character and move on
      buffer.write(char);
      i++;
    }
    
    result = buffer.toString();
    
    // Step 5: Fix single-quoted property names
    result = result.replaceAllMapped(
      RegExp(r"'([a-zA-Z_][a-zA-Z0-9_]*)'\s*:"),
      (match) => '"${match.group(1)}":',
    );
    
    // Step 6: Fix single-quoted string values
    result = result.replaceAllMapped(
      RegExp(r":\s*'((?:[^'\\]|\\.)*)'"),
      (match) {
        final value = match.group(1) ?? '';
        final escaped = value.replaceAll('"', '\\"');
        return ': "$escaped"';
      },
    );
    
    // Step 7: Remove trailing commas
    result = result.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    
    // Step 8: Final pass - catch any remaining unquoted properties using regex
    // This is a safety net for edge cases - be VERY aggressive
    // Match ANY word-like sequence followed by colon that's not already quoted
    int passCount = 0;
    String previousResult = '';
    while (passCount < 5 && result != previousResult) {
      previousResult = result;
      result = result.replaceAllMapped(
        RegExp(r'([{,]\s*|^\s*|,\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:', multiLine: true),
        (match) {
          final prefix = match.group(1) ?? '';
          final propName = match.group(2) ?? '';
          final beforePos = match.start;
          
          // Check if already quoted - be VERY thorough
          if (beforePos > 0) {
            final before = result.substring(0, beforePos);
            // Check last few characters to see if property is already quoted
            final lastChars = before.length > 20 ? before.substring(before.length - 20) : before;
            // Check multiple patterns to see if already quoted
            if (lastChars.endsWith('"') || 
                lastChars.contains('"$propName"') ||
                lastChars.endsWith('"$propName"') ||
                before.endsWith('"')) {
              return match.group(0) ?? '';
            }
          }
          
          // ALWAYS quote the property name if we get here
          return '$prefix"$propName":';
        },
      );
      passCount++;
    }
    
    return result.trim();
  }

  /// Robust JSON sanitization function
  /// Removes markdown, extracts JSON object, completes incomplete JSON, and validates the result
  String? _sanitizeJsonResponse(String rawResponse) {
    if (rawResponse.isEmpty) {
      debugPrint('⚠️ Raw response is empty');
      return null;
    }

    String cleaned = rawResponse.trim();

    // Step 1: Remove markdown code blocks
    cleaned = cleaned.replaceAll(RegExp(r'```json\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```json'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```'), '');
    cleaned = cleaned.trim();

    // Step 2: Force double quotes - replace single quotes with double quotes
    // Handle single-quoted strings (property names and values)
    // Pattern: 'text' or 'text with "quotes"'
    cleaned = cleaned.replaceAllMapped(RegExp(r"'([^'\\]*(\\.[^'\\]*)*)'"), (match) {
      final content = match.group(1) ?? '';
      // Escape any existing double quotes in the content
      final escaped = content.replaceAll('"', '\\"');
      return '"$escaped"';
    });

    // Step 3: Extract JSON - handle incomplete JSON (cut off responses)
    final firstBrace = cleaned.indexOf('{');
    if (firstBrace == -1) {
      debugPrint('⚠️ No opening brace { found in response');
      return null;
    }

    // Extract from first { to end (even if no closing })
    String extractedJson = cleaned.substring(firstBrace);
    
    // Step 4: Complete the JSON if it's cut off
    // Count opening and closing braces to see if JSON is incomplete
    int openBraces = 0;
    int closeBraces = 0;
    int openBrackets = 0;
    int closeBrackets = 0;
    bool inString = false;
    bool escapeNext = false;
    
    for (int i = 0; i < extractedJson.length; i++) {
      final char = extractedJson[i];
      
      if (escapeNext) {
        escapeNext = false;
        continue;
      }
      
      if (char == '\\') {
        escapeNext = true;
        continue;
      }
      
      if (char == '"') {
        inString = !inString;
        continue;
      }
      
      if (!inString) {
        if (char == '{') openBraces++;
        if (char == '}') closeBraces++;
        if (char == '[') openBrackets++;
        if (char == ']') closeBrackets++;
      }
    }
    
    // Complete the JSON by adding missing closing braces/brackets
    String completedJson = extractedJson;
    
    // Step 4a: Close any incomplete strings (if cut off in middle of string)
    // Check if the JSON ends with an incomplete string (starts with " but doesn't close)
    // Pattern: ends with ", " or just " followed by whitespace
    final incompleteStringPattern = RegExp(r'":\s*"([^"]*)$');
    final incompleteStringMatch = incompleteStringPattern.firstMatch(completedJson);
    if (incompleteStringMatch != null) {
      // We have an incomplete string value, close it
      final incompleteContent = incompleteStringMatch.group(1) ?? '';
      // Remove the incomplete content and close the string
      completedJson = completedJson.substring(0, completedJson.length - incompleteContent.length) + '"';
      debugPrint('✅ Closed incomplete string value');
    }
    
    // Also check for incomplete string at the very end (starts with " but no closing quote)
    if (completedJson.trim().endsWith('"') == false) {
      // Check if last non-whitespace character before end is a quote
      final trimmed = completedJson.trimRight();
      if (trimmed.endsWith('"')) {
        // String is already closed, nothing to do
      } else {
        // Check if we're in the middle of a string (last quote is opening, not closing)
        final lastQuoteIndex = trimmed.lastIndexOf('"');
        if (lastQuoteIndex != -1) {
          // Count quotes before this one to see if it's an opening or closing quote
          int quoteCount = 0;
          bool escapeNext = false;
          for (int i = 0; i <= lastQuoteIndex; i++) {
            if (escapeNext) {
              escapeNext = false;
              continue;
            }
            if (trimmed[i] == '\\') {
              escapeNext = true;
              continue;
            }
            if (trimmed[i] == '"') {
              quoteCount++;
            }
          }
          // If odd number of quotes, we have an unclosed string
          if (quoteCount % 2 == 1) {
            // Close the string
            completedJson = trimmed + '"';
            debugPrint('✅ Closed unclosed string at end');
          }
        }
      }
    }
    
    // Step 4b: Add missing closing braces/brackets
    if (openBraces > closeBraces) {
      // Remove trailing comma if present before adding closing brace
      completedJson = completedJson.replaceAll(RegExp(r',\s*$'), '');
      // Add missing closing braces
      for (int i = 0; i < (openBraces - closeBraces); i++) {
        completedJson += '}';
      }
      debugPrint('✅ Completed JSON: Added ${openBraces - closeBraces} closing brace(s)');
    }
    
    if (openBrackets > closeBrackets) {
      // Remove trailing comma if present before adding closing bracket
      completedJson = completedJson.replaceAll(RegExp(r',\s*$'), '');
      // Add missing closing brackets
      for (int i = 0; i < (openBrackets - closeBrackets); i++) {
        completedJson += ']';
      }
      debugPrint('✅ Completed JSON: Added ${openBrackets - closeBrackets} closing bracket(s)');
    }

    // Step 5: Remove trailing commas before closing braces and brackets
    // This must happen AFTER completing the JSON structure
    // Remove trailing commas before }
    completedJson = completedJson.replaceAll(RegExp(r',\s*}'), '}');
    // Remove trailing commas before ]
    completedJson = completedJson.replaceAll(RegExp(r',\s*]'), ']');
    // Remove trailing commas before closing braces in nested structures (multiple passes)
    for (int i = 0; i < 5; i++) {
      final before = completedJson;
      completedJson = completedJson.replaceAll(RegExp(r',\s*}'), '}');
      completedJson = completedJson.replaceAll(RegExp(r',\s*]'), ']');
      if (before == completedJson) break; // No more changes
    }
    // Remove trailing commas at the end of the string
    completedJson = completedJson.replaceAll(RegExp(r',\s*$'), '');

    // Step 6: Final validation
    if (completedJson.isEmpty) {
      debugPrint('⚠️ Cleaned JSON string is empty');
      return null;
    }

    if (!completedJson.startsWith('{')) {
      debugPrint('⚠️ Cleaned string does not start with {');
      return null;
    }

    // If it still doesn't end with }, try to complete it one more time
    if (!completedJson.endsWith('}')) {
      // Count braces again after all processing
      final finalOpenBraces = completedJson.split('{').length - 1;
      final finalCloseBraces = completedJson.split('}').length - 1;
      if (finalOpenBraces > finalCloseBraces) {
        completedJson += '}';
        debugPrint('✅ Added final closing brace');
      }
    }

    debugPrint('✅ Sanitized JSON: Length ${completedJson.length}, starts with {, ends with ${completedJson.endsWith('}') ? '}' : 'incomplete'}');
    return completedJson;
  }

  /// Robust JSON parsing with comprehensive error handling
  /// Returns parsed JSON or throws a detailed exception
  Map<String, dynamic> _parseJsonSafely(String rawResponse, {String context = 'JSON parsing'}) {
    // Step 1: Sanitize the response
    final cleanedJson = _sanitizeJsonResponse(rawResponse);
    
    if (cleanedJson == null || cleanedJson.isEmpty) {
      throw FormatException(
        '$context: Cleaned JSON string is empty or null. '
        'Raw response length: ${rawResponse.length}, '
        'First 200 chars: ${rawResponse.length > 200 ? rawResponse.substring(0, 200) : rawResponse}'
      );
    }

    // Step 2: Try to parse with detailed error logging
    try {
      final parsed = json.decode(cleanedJson) as Map<String, dynamic>;
      debugPrint('✅ Successfully parsed JSON ($context)');
      return parsed;
    } catch (e) {
      // Detailed error logging
      debugPrint('❌ JSON parse error ($context): $e');
      debugPrint('❌ Raw response length: ${rawResponse.length}');
      debugPrint('❌ Cleaned JSON length: ${cleanedJson.length}');
      debugPrint('❌ Cleaned JSON (first 1000 chars): ${cleanedJson.length > 1000 ? cleanedJson.substring(0, 1000) : cleanedJson}');
      
      // Extract error position if available
      if (e is FormatException) {
        final errorMsg = e.toString();
        final positionMatch = RegExp(r'position (\d+)').firstMatch(errorMsg);
        if (positionMatch != null) {
          final errorPosition = int.tryParse(positionMatch.group(1) ?? '0') ?? 0;
          debugPrint('❌ Error at position: $errorPosition');
          
          if (errorPosition > 0 && errorPosition < cleanedJson.length) {
            final start = (errorPosition - 50).clamp(0, cleanedJson.length);
            final end = (errorPosition + 50).clamp(0, cleanedJson.length);
            debugPrint('❌ Problematic section (chars ${start}-${end}): ${cleanedJson.substring(start, end)}');
            debugPrint('❌ Character at position $errorPosition: "${cleanedJson[errorPosition]}" (code: ${cleanedJson.codeUnitAt(errorPosition)})');
            
            // Show surrounding context
            if (errorPosition > 20) {
              debugPrint('❌ Context before error: ${cleanedJson.substring(errorPosition - 20, errorPosition)}');
            }
            if (errorPosition < cleanedJson.length - 20) {
              debugPrint('❌ Context after error: ${cleanedJson.substring(errorPosition, errorPosition + 20)}');
            }
          }
        }
      }
      
      // Re-throw with context
      throw FormatException(
        '$context: Failed to parse JSON. Error: $e. '
        'Cleaned JSON length: ${cleanedJson.length}, '
        'First 500 chars: ${cleanedJson.length > 500 ? cleanedJson.substring(0, 500) : cleanedJson}',
        e
      );
    }
  }

  Map<String, dynamic> _parseSemanticResponse(String response) {
    try {
      debugPrint('📥 Raw response length: ${response.length}');
      debugPrint('📥 First 500 chars: ${response.length > 500 ? response.substring(0, 500) : response}');
      
      // Step 1: Sanitize the response (removes markdown, extracts JSON)
      final sanitizedJson = _sanitizeJsonResponse(response);
      
      if (sanitizedJson == null || sanitizedJson.isEmpty) {
        throw FormatException(
          'Failed to sanitize JSON response: Response is empty or contains no valid JSON object. '
          'Raw response length: ${response.length}, '
          'First 200 chars: ${response.length > 200 ? response.substring(0, 200) : response}'
        );
      }
      
      // Step 2: Use comprehensive JSON repair
      String cleanJson = _repairJson(sanitizedJson);
      
      debugPrint('📥 Cleaned JSON length: ${cleanJson.length}');
      debugPrint('📥 First 500 chars of cleaned: ${cleanJson.length > 500 ? cleanJson.substring(0, 500) : cleanJson}');
      
      // Step 3: Try to parse JSON with multiple repair attempts
      Map<String, dynamic>? jsonData;
      int attempt = 0;
      String currentJson = cleanJson;
      bool parseSuccess = false;
      
      while (attempt < 3 && !parseSuccess) {
        try {
          // Use the robust parsing function (includes sanitization, validation, and error logging)
          jsonData = _parseJsonSafely(currentJson, context: 'Semantic response parsing (attempt ${attempt + 1})');
          parseSuccess = true;
        } catch (jsonError) {
          attempt++;
          debugPrint('❌ JSON parse error (attempt $attempt): $jsonError');
          
          if (attempt >= 3) {
            // Last attempt - show detailed error info
            debugPrint('❌ Problematic JSON (first 1000 chars): ${currentJson.length > 1000 ? currentJson.substring(0, 1000) : currentJson}');
            
            // Extract error position
            int errorPosition = 0;
            final positionMatch = RegExp(r'position (\d+)').firstMatch(jsonError.toString());
            if (positionMatch != null) {
              errorPosition = int.tryParse(positionMatch.group(1) ?? '0') ?? 0;
              debugPrint('❌ Error at position $errorPosition');
              
              if (errorPosition > 0 && errorPosition < currentJson.length) {
                final start = (errorPosition - 50).clamp(0, currentJson.length);
                final end = (errorPosition + 50).clamp(0, currentJson.length);
                debugPrint('❌ Problematic section: ${currentJson.substring(start, end)}');
                debugPrint('❌ Character at position $errorPosition: "${currentJson[errorPosition]}" (code: ${currentJson.codeUnitAt(errorPosition)})');
              }
            }
            
            // Try one final ULTRA-AGGRESSIVE repair with multiple passes
            // Run repair function multiple times to catch all edge cases
            for (int repairIteration = 0; repairIteration < 5; repairIteration++) {
              currentJson = _repairJson(currentJson);
              
              // Multiple regex passes to catch ALL unquoted properties
              for (int regexPass = 0; regexPass < 5; regexPass++) {
                final beforeRegex = currentJson;
                currentJson = currentJson.replaceAllMapped(
                  RegExp(r'([{,]\s*|^\s*|,\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:', multiLine: true),
                  (match) {
                    final prefix = match.group(1) ?? '';
                    final propName = match.group(2) ?? '';
                    final beforePos = match.start;
                    
                    // Check if already quoted - be very thorough
                    if (beforePos > 0) {
                      final before = currentJson.substring(0, beforePos);
                      final lastChars = before.length > 10 
                          ? before.substring(before.length - 10) 
                          : before;
                      if (lastChars.endsWith('"') || 
                          lastChars.contains('"$propName"') ||
                          before.endsWith('"')) {
                        return match.group(0) ?? '';
                      }
                    }
                    return '$prefix"$propName":';
                  },
                );
                
                // If no changes were made, break early
                if (currentJson == beforeRegex) break;
              }
              
              // Remove trailing commas
              currentJson = currentJson.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
            }
            
            // Before final attempt, do one more character-by-character pass
            // This is the most aggressive repair possible
            final ultraRepaired = StringBuffer();
            bool inStr = false;
            bool escNext = false;
            int pos = 0;
            
            while (pos < currentJson.length) {
              final ch = currentJson[pos];
              
              if (escNext) {
                ultraRepaired.write(ch);
                escNext = false;
                pos++;
                continue;
              }
              
              if (ch == '\\') {
                ultraRepaired.write(ch);
                escNext = true;
                pos++;
                continue;
              }
              
              if (ch == '"') {
                inStr = !inStr;
                ultraRepaired.write(ch);
                pos++;
                continue;
              }
              
              if (!inStr) {
                final remaining = currentJson.substring(pos);
                final propMatch = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*:').firstMatch(remaining);
                if (propMatch != null) {
                  final propName = propMatch.group(1)!;
                  final before = ultraRepaired.toString();
                  final lastChars = before.length > 15 
                      ? before.substring(before.length - 15) 
                      : before;
                  
                  // Only quote if not already quoted
                  if (!lastChars.endsWith('"') && 
                      !lastChars.contains('"$propName"')) {
                    ultraRepaired.write('"$propName":');
                    pos += propMatch.end;
                    continue;
                  }
                }
              }
              
              ultraRepaired.write(ch);
              pos++;
            }
            
            currentJson = ultraRepaired.toString();
            currentJson = currentJson.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
            
            try {
              jsonData = _parseJsonSafely(currentJson, context: 'Final ultra-aggressive repair attempt');
              debugPrint('✅ Successfully parsed after ULTRA-AGGRESSIVE character-by-character repair!');
              parseSuccess = true;
            } catch (e3) {
              debugPrint('❌ All repair attempts failed: $e3');
              debugPrint('❌ Final JSON (first 500 chars): ${currentJson.length > 500 ? currentJson.substring(0, 500) : currentJson}');
              throw Exception('Failed to parse AI response after all repair attempts: $e3');
            }
          } else {
            // Try another repair pass with multiple iterations
            currentJson = _repairJson(currentJson);
            // Multiple regex passes to be thorough
            for (int regexPass = 0; regexPass < 3; regexPass++) {
              currentJson = currentJson.replaceAllMapped(
                RegExp(r'([{,]\s*|^\s*|,\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:', multiLine: true),
                (match) {
                  final prefix = match.group(1) ?? '';
                  final propName = match.group(2) ?? '';
                  final beforePos = match.start;
                  // Check if already quoted
                  if (beforePos > 0) {
                    final before = currentJson.substring(0, beforePos);
                    final lastChars = before.length > 5 
                        ? before.substring(before.length - 5) 
                        : before;
                    if (lastChars.endsWith('"') || 
                        lastChars.contains('"$propName"') ||
                        before.endsWith('"')) {
                      return match.group(0) ?? '';
                    }
                  }
                  return '$prefix"$propName":';
                },
              );
            }
            currentJson = currentJson.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
            debugPrint('🔄 Retrying with repaired JSON (attempt $attempt)');
          }
        }
      }
      
      if (jsonData == null) {
        throw Exception('Failed to parse JSON after all attempts');
      }
      
      // Handle empty response gracefully
      if (jsonData.isEmpty) {
        debugPrint('⚠️ Empty JSON response from AI');
        return {
          'isValid': false,
          'poData': null,
          'summary': 'AI returned an empty response. Please try again.',
        };
      }
      
      final isValid = jsonData['isValid'] as bool? ?? false;
      final poDataJson = jsonData['poData'] as Map<String, dynamic>?;
      final summary = jsonData['summary'] as String? ?? 'Purchase Order extracted successfully.';
      
      PurchaseOrder? poData;
      if (poDataJson != null && poDataJson.isNotEmpty) {
        try {
          // Convert N/A to null, handle null values gracefully
          final cleanedPoData = Map<String, dynamic>.from(poDataJson);
          
          // Handle N/A values and null strings - but preserve actual values
          if (cleanedPoData['poNumber'] == 'N/A') {
            cleanedPoData['poNumber'] = null;
          }
          // Don't set customerName to null if it has a value - preserve it
          if (cleanedPoData['customerName'] == 'N/A') {
            cleanedPoData['customerName'] = null;
          }
          // Ensure customerName is preserved if it exists
          if (cleanedPoData['customerName'] != null && cleanedPoData['customerName'].toString().trim().isNotEmpty) {
            // Keep the value as is
            debugPrint('✅ Preserving customerName: ${cleanedPoData['customerName']}');
          }
          
          // Handle null numeric fields - but preserve actual values
          if (cleanedPoData['totalAmount'] == null || cleanedPoData['totalAmount'] == 0.0) {
            // Only set to 0.0 if truly null, otherwise preserve the value
            if (cleanedPoData['totalAmount'] == null) {
              cleanedPoData['totalAmount'] = 0.0;
            }
          } else {
            // Ensure totalAmount is a number
            final totalAmountValue = cleanedPoData['totalAmount'];
            if (totalAmountValue is num) {
              cleanedPoData['totalAmount'] = totalAmountValue.toDouble();
            } else if (totalAmountValue is String) {
              cleanedPoData['totalAmount'] = double.tryParse(totalAmountValue) ?? 0.0;
            }
            debugPrint('✅ Preserving totalAmount: ${cleanedPoData['totalAmount']}');
          }
          
          // Handle null lineItems
          if (cleanedPoData['lineItems'] == null) {
            cleanedPoData['lineItems'] = <Map<String, dynamic>>[];
          }
          
          // Ensure lineItems is a list
          final lineItems = cleanedPoData['lineItems'];
          if (lineItems is! List) {
            cleanedPoData['lineItems'] = <Map<String, dynamic>>[];
          }
          
          // Clean each line item to handle nulls and apply fuzzy matching
          if (lineItems is List) {
            final cleanedItems = <Map<String, dynamic>>[];
            final catalogService = CatalogService();
            
            for (var item in lineItems) {
              if (item is Map<String, dynamic>) {
                final cleanedItem = Map<String, dynamic>.from(item);
                
                // Ensure required numeric fields have defaults
                if (cleanedItem['quantity'] == null) cleanedItem['quantity'] = 0.0;
                
                // FUZZY ITEM MATCHING: Match against productCatalog dynamically
                // If unitPrice is missing or 0, try to match from catalog
                final itemName = (cleanedItem['itemName'] as String? ?? '').trim();
                final description = (cleanedItem['description'] as String? ?? '').trim();
                final currentUnitPrice = (cleanedItem['unitPrice'] as num?)?.toDouble() ?? 0.0;
                
                if (currentUnitPrice == 0.0 && (itemName.isNotEmpty || description.isNotEmpty)) {
                  // Try fuzzy matching against catalog
                  final matchedPrice = catalogService.matchItemPrice(itemName, description: description);
                  if (matchedPrice > 0.0) {
                    cleanedItem['unitPrice'] = matchedPrice;
                    debugPrint('✅ Fuzzy matched: "$itemName" -> ${matchedPrice} AED');
                  }
                }
                
                // Ensure unitPrice is set (use matched price or keep existing)
                if (cleanedItem['unitPrice'] == null) cleanedItem['unitPrice'] = 0.0;
                
                // Calculate total if missing
                if (cleanedItem['total'] == null) {
                  final qty = (cleanedItem['quantity'] as num?)?.toDouble() ?? 0.0;
                  final price = (cleanedItem['unitPrice'] as num?)?.toDouble() ?? 0.0;
                  cleanedItem['total'] = qty * price;
                }
                
                cleanedItems.add(cleanedItem);
              }
            }
            cleanedPoData['lineItems'] = cleanedItems;
          }
          
          final jsonString = json.encode(cleanedPoData);
          poData = _parseExtractedData(jsonString, '');
          debugPrint('✅ Successfully parsed PO data from semantic extraction');
        } catch (e) {
          debugPrint('Error parsing PO data: $e');
          poData = null;
        }
      } else {
        debugPrint('⚠️ poData is null or empty in response');
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

CRITICAL: Return ONLY a raw JSON object. Do not include any conversational text, backticks, or markdown formatting.

Return ONLY valid JSON with this exact structure (NO MARKDOWN, NO CODE BLOCKS, NO EXPLANATIONS):
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
2. EXTRACT THESE FIELDS:
   - PO Number: Look for "PO Number:", "PO:", "PO #", "Order No", "Purchase Order Number"
   - Quotation Reference/Quote No: Look for "Quotation Number:", "Quotation:", "Quote No:", "Quote #:", "QTN:", "Quotation Reference:", "Ref Quotation:", "QUOTATION REFERENCE NO"
   - Vendor Name: Look for "Vendor Name:", "Vendor:", "Supplier Name:", "Supplier:", "Customer Name:", "Customer:", "Bill To:", "Ship To:"
   - PO Date: Look for "PO Date:", "Date:", "Order Date:", "Issue Date:" (convert to YYYY-MM-DD format)
   - Expiry Date: Look for "Expiry Date:", "Valid Until:", "Expiration Date:" (convert to YYYY-MM-DD format or null)
   - Customer Address: Look for "Address:", "Bill To Address:", "Ship To Address:"
   - Customer Email: Look for "Email:", "Email Address:", "Contact Email:"
   - Total Amount: Look for "Grand Total:", "Total Amount:", "Total:", "Amount Due:" (extract numeric value only)
   - Currency: Look for currency code (AED, USD, INR, EUR, etc.) from amount fields
   - Line Items: Extract ALL line items from tables or lists
   - Description: Extract description for each line item
3. For line items: Extract from table with columns: Item No | Description | Part Number | Qty | Unit Price | Total
   - Extract ALL rows from the table
   - Use Description column for itemName
   - Use Part Number/Material Code column for itemCode (if available)
   - Extract description field for each item
   - Use Qty column for quantity
   - Use Unit Price column for unitPrice
   - Use Total column for total
4. For dates: Convert to YYYY-MM-DD format
   - "22 November 2025" → "2025-11-22"
   - "November 22, 2025" → "2025-11-22"
5. For amounts: Extract ONLY the numeric value, remove currency symbols and commas
   - "12127.50 AED" → 12127.50
   - "1,127.50" → 1127.50
6. DO NOT use sample data, test data, or placeholder values
7. If a field is not found, use null (not "N/A" or "Unknown")

Return ONLY valid JSON (no markdown, no code blocks, no explanations):
{
  "poNumber": "exact PO number from document or null",
  "poDate": "date in YYYY-MM-DD format or null",
  "expiryDate": "date in YYYY-MM-DD format or null",
  "quotationReference": "quotation number or reference if found in document, else null",
  "vendorName": "vendor/supplier/customer name from document or null",
  "customerAddress": "address if found, else null",
  "customerEmail": "email if found, else null",
  "totalAmount": numeric_value_only,
  "currency": "currency code (AED, INR, USD, EUR, etc.) if found, else null",
  "lineItems": [
    {
      "itemName": "description from table",
      "itemCode": "part number from table or null",
      "description": "description text for the item or null",
      "quantity": numeric_value,
      "unit": "pcs",
      "unitPrice": numeric_value,
      "total": numeric_value
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
      final quotationReference = jsonData['quotationReference']?.toString().trim();
      final vendorName = jsonData['vendorName']?.toString().trim();
      final customerAddress = jsonData['customerAddress']?.toString().trim();
      final customerEmail = jsonData['customerEmail']?.toString().trim();
      
      // Use vendorName as customerName, fallback to 'Unknown' if not found
      String finalCustomerName = (vendorName != null && vendorName.isNotEmpty && vendorName != 'N/A' && vendorName.toLowerCase() != 'unknown')
          ? vendorName
          : 'Unknown';
      
      // Extract currency
      String? extractedCurrency = jsonData['currency']?.toString().trim().toUpperCase();
      if (extractedCurrency == null || extractedCurrency.isEmpty || extractedCurrency == 'NULL') {
        // Try to extract currency from original text
        final currencyPatterns = [
          RegExp(r'Grand\s*Total[:\s]+[\d,]+\.?\d*\s*([A-Z]{3})', caseSensitive: false),
          RegExp(r'Total[:\s]+[\d,]+\.?\d*\s*([A-Z]{3})', caseSensitive: false),
          RegExp(r'Unit\s*Price\s*\(([A-Z]{3})\)', caseSensitive: false),
          RegExp(r'Total\s*\(([A-Z]{3})\)', caseSensitive: false),
          RegExp(r'([A-Z]{3})\s*\d+\.?\d*', caseSensitive: false),
        ];
        
        for (final pattern in currencyPatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            extractedCurrency = match.group(1)!.trim().toUpperCase();
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
          } else {
            extractedCurrency = 'AED'; // Default
          }
        }
      }
      
      // Extract total amount
      dynamic totalAmount = jsonData['totalAmount'];
      double finalTotalAmount = 0.0;
      if (totalAmount != null) {
        if (totalAmount is num) {
          finalTotalAmount = totalAmount.toDouble();
        } else if (totalAmount is String) {
          final cleanAmount = totalAmount.replaceAll(RegExp(r'[^\d.]'), '');
          finalTotalAmount = double.tryParse(cleanAmount) ?? 0.0;
        }
      }
      
      // If total is 0 or missing, calculate from line items
      if (finalTotalAmount == 0.0 && lineItems.isNotEmpty) {
        finalTotalAmount = lineItems.fold(0.0, (sum, item) => sum + item.total);
      }
      
      // If still 0, try to extract from original text
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
      
      // Validate PO number
      String finalPONumber = poNumber ?? '';
      if (finalPONumber.isEmpty || finalPONumber == 'N/A' || finalPONumber.toLowerCase() == 'unknown' || finalPONumber.contains('sample') || finalPONumber.contains('test')) {
        // Try multiple patterns for PO number
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
            if (extracted.isNotEmpty && !extracted.toLowerCase().contains('sample') && !extracted.toLowerCase().contains('test')) {
              finalPONumber = extracted;
              break;
            }
          }
        }
      }
      
      if (finalPONumber.isEmpty || finalPONumber == 'N/A') {
        finalPONumber = 'N/A';
      }
      
      // Validate customer name
      if (finalCustomerName.isEmpty || finalCustomerName == 'Unknown') {
        // Try to extract from text
        final patterns = [
          RegExp(r'Customer\s*Name[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Customer\s*Name:\s*(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Customer[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
          RegExp(r'Company[:\s]+(.+?)(?:\n|Contact|Address|Email|Phone|$)', caseSensitive: false),
        ];
        
        for (final pattern in patterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            final extracted = match.group(1)!.trim();
            finalCustomerName = extracted.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (finalCustomerName.isNotEmpty && !finalCustomerName.toLowerCase().contains('sample') && !finalCustomerName.toLowerCase().contains('test')) {
              break;
            }
          }
        }
        
        if (finalCustomerName.isEmpty || finalCustomerName == 'Unknown') {
          finalCustomerName = 'Unknown';
        }
      }
      
      // Log line items count
      debugPrint('✅ Line items count: ${lineItems.length}');
      if (lineItems.isNotEmpty) {
        debugPrint('✅ First line item: ${lineItems.first.itemName}, Qty: ${lineItems.first.quantity}, Price: ${lineItems.first.unitPrice}');
      }
      
      return PurchaseOrder(
        poNumber: finalPONumber,
        poDate: poDate,
        expiryDate: finalExpiryDate,
        customerName: finalCustomerName,
        customerAddress: customerAddress?.isNotEmpty == true ? customerAddress : null,
        customerEmail: customerEmail?.isNotEmpty == true ? customerEmail : null,
        totalAmount: finalTotalAmount,
        currency: extractedCurrency ?? 'AED',
        terms: null,
        notes: null,
        lineItems: lineItems,
        createdAt: DateTime.now(),
        status: status,
        quotationReference: quotationReference,
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

