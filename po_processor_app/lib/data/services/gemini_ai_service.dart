import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';
import 'package:pdfx/pdfx.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../domain/entities/quotation.dart';
import 'catalog_service.dart';

class GeminiAIService {
  // Singleton instance
  static final GeminiAIService _instance = GeminiAIService._internal();
  factory GeminiAIService() => _instance;
  GeminiAIService._internal();

  GenerativeModel? _modelOrNull;
  GenerativeModel? _jsonModelOrNull;

  /// Lazy init: create models when first used so .env is already loaded by main().
  void _ensureModels() {
    if (_modelOrNull != null) return;
    if (!AppConstants.hasGeminiApiKey) {
      debugPrint('⚠️ GeminiAIService: GEMINI_API_KEY not set. Add GEMINI_API_KEY to .env in po_processor_app.');
      return;
    }
    _modelOrNull = GenerativeModel(
      model: AppConstants.geminiModel,
      apiKey: AppConstants.geminiApiKey,
    );
    _jsonModelOrNull = GenerativeModel(
      model: AppConstants.geminiModel,
      apiKey: AppConstants.geminiApiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        maxOutputTokens: 2048
      ),
    );
    debugPrint('✅ GeminiAIService: model initialized (key from .env)');
  }

  GenerativeModel get _m {
    _ensureModels();
    return _modelOrNull ?? (throw StateError(
      'GEMINI_API_KEY missing. Add it to .env in po_processor_app (see .env.example).'
    ));
  }
  GenerativeModel get _j {
    _ensureModels();
    return _jsonModelOrNull ?? (throw StateError(
      'GEMINI_API_KEY missing. Add it to .env in po_processor_app (see .env.example).'
    ));
  }
  
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
  /// Sanitize PDF text by removing technical headers, gibberish, SAP metadata, postscript streams, and normalizing whitespace
  /// This acts like pdfplumber's extract_text() - only extracts visible characters, filters metadata
  String sanitizePdfText(String rawText) {
    // 1. Remove PDF technical headers and object markers
    String cleanText = rawText.replaceAll(RegExp(r'(\%PDF-|obj|endobj|xref|trailer|startxref|[0-9]+\s[0-9]+\sobj)'), '');
    
    // 2. Remove PostScript/PDF stream metadata (like pdfplumber filters)
    cleanText = cleanText.replaceAll(RegExp(r'/FlateDecode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/BitsPerComponent\s+\d+', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/RunLengthDecode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/DCTDecode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/CCITTFaxDecode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/LZWDecode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/ASCII85Decode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'/ASCIIHexDecode', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'stream\s+.*?endstream', caseSensitive: false, dotAll: true), ' ');
    
    // 3. Remove SAP-specific metadata and corrupted text patterns
    cleanText = cleanText.replaceAll(RegExp(r'\bZMEDRUCK\b', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'\bSAP_WFRT\b', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'\bNetWeaver\b', caseSensitive: false), '');
    cleanText = cleanText.replaceAll(RegExp(r'\bVER\s+[\d.]+', caseSensitive: false), ''); // VER 8.00
    cleanText = cleanText.replaceAll(RegExp(r'~\s*[\dK]+\s*=\s*[a-z]+', caseSensitive: false), ''); // ~ 7K=bl
    
    // 4. Remove corrupted text patterns (random character sequences like ];P+ e;*A[Xs)
    cleanText = cleanText.replaceAll(RegExp(r'[\]\[;P+\s*e;*A\[Xs]+', caseSensitive: false), ' ');
    cleanText = cleanText.replaceAll(RegExp(r'[<>{}[\]\\|`~!@#$%^&*()_+\-=]{5,}'), ' '); // Long sequences of special chars
    
    // 5. Remove font mapping corruption patterns (common in SAP PDFs)
    // Pattern: short alphanumeric sequences that look like corrupted text
    cleanText = cleanText.replaceAllMapped(RegExp(r'\b[A-Za-z]{1,2}\d+[A-Za-z]{1,2}\b'), (match) {
      // Only remove if it looks like corrupted text (very short patterns)
      if (match.group(0)!.length < 5) return ' ';
      return match.group(0)!;
    });
    
    // 6. Remove long strings of non-alphanumeric "gibberish" (postscript artifacts)
    cleanText = cleanText.replaceAll(RegExp(r'[^\x20-\x7E\n\t]'), ' '); 
    
    // 7. Remove sequences that look like postscript commands
    cleanText = cleanText.replaceAll(RegExp(r'/[A-Z][a-zA-Z]+\s+\d+', caseSensitive: false), ' ');
    cleanText = cleanText.replaceAll(RegExp(r'\d+\s+\d+\s+[a-z]+\s+\d+', caseSensitive: false), ' ');
    
    // 8. Collapse multiple spaces/newlines into single ones for token efficiency
    cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return cleanText;
  }

  /// Extract text from PDF bytes using OCR (Primary method for SAP-encoded PDFs)
  /// Converts PDF pages to high-resolution images (2.0x scale), then uses ML Kit OCR to extract text
  /// This bypasses Identity-H encoding issues in SAP PDFs
  Future<String> extractTextFromPDFBytesWithOCR(Uint8List bytes, String fileName) async {
    try {
      debugPrint('=== STARTING OCR-BASED PDF TEXT EXTRACTION ===');
      debugPrint('PDF file: $fileName, Size: ${bytes.length} bytes');
      
      // Initialize text recognizer
      final textRecognizer = TextRecognizer();
      final extractedText = StringBuffer();
      
      try {
        // Load PDF using pdfx
        final pdf = await PdfDocument.openData(bytes);
        final pageCount = pdf.pagesCount;
        debugPrint('📄 PDF has $pageCount pages');
        
        // Process each page
        for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
          debugPrint('📄 Processing page ${pageIndex + 1}/$pageCount with OCR...');
          
          try {
            // Get page
            final page = await pdf.getPage(pageIndex + 1);
            
            // Get page dimensions
            final pageWidth = await page.width;
            final pageHeight = await page.height;
            
            // Render page as image with high resolution (2.0x scale for better OCR accuracy)
            final scaleFactor = 2.0;
            final renderWidth = pageWidth * scaleFactor;
            final renderHeight = pageHeight * scaleFactor;
            
            debugPrint('📄 Rendering page ${pageIndex + 1} at ${renderWidth.toInt()}x${renderHeight.toInt()} (${scaleFactor}x scale)');
            final pageImage = await page.render(
              width: renderWidth,
              height: renderHeight,
            );
            
            if (pageImage != null) {
              // Convert ui.Image to bytes for ML Kit
              // pdfx 2.9.2 returns PdfPageImage which should extend ui.Image
              // Cast to ui.Image to access toByteData
              final uiImage = pageImage as ui.Image;
              final imageBytes = await uiImage.toByteData(format: ui.ImageByteFormat.png);
              if (imageBytes != null) {
                final bytes = imageBytes.buffer.asUint8List();
                final width = uiImage.width;
                final height = uiImage.height;
                
                debugPrint('📄 Page ${pageIndex + 1} image: ${width}x${height}, ${bytes.length} bytes');
                
                // Create InputImage from PNG bytes for ML Kit
                // ML Kit requires proper metadata
                final inputImage = InputImage.fromBytes(
                  bytes: bytes,
                  metadata: InputImageMetadata(
                    size: Size(width.toDouble(), height.toDouble()),
                    rotation: InputImageRotation.rotation0deg,
                    format: InputImageFormat.yuv420, // ML Kit standard format for images
                    bytesPerRow: bytes.length ~/ height,
                  ),
                );
                
                // Perform OCR
                debugPrint('🔍 Running OCR on page ${pageIndex + 1}...');
                final recognizedText = await textRecognizer.processImage(inputImage);
                
                // Extract text from all blocks and lines
                final pageText = StringBuffer();
                for (final block in recognizedText.blocks) {
                  for (final line in block.lines) {
                    pageText.writeln(line.text);
                  }
                }
                
                final pageTextStr = pageText.toString();
                extractedText.writeln(pageTextStr);
                
                debugPrint('✅ Page ${pageIndex + 1} OCR completed: ${pageTextStr.length} characters');
                debugPrint('📄 First 200 chars: ${pageTextStr.length > 200 ? pageTextStr.substring(0, 200) : pageTextStr}');
              } else {
                debugPrint('⚠️ Failed to convert page ${pageIndex + 1} image to bytes');
              }
            } else {
              debugPrint('⚠️ Failed to render page ${pageIndex + 1} as image');
            }
          } catch (e) {
            debugPrint('⚠️ Error processing page ${pageIndex + 1}: $e');
          }
        }
        
        await pdf.close();
      } finally {
        await textRecognizer.close();
      }
      
      final result = extractedText.toString();
      debugPrint('✅ OCR extraction completed: ${result.length} total characters');
      if (result.isNotEmpty) {
        debugPrint('📄 First 1000 chars: ${result.length > 1000 ? result.substring(0, 1000) : result}');
      } else {
        debugPrint('⚠️ OCR extraction returned empty text');
      }
      
      return result;
    } catch (e) {
      debugPrint('❌ Error in OCR-based PDF text extraction: $e');
      debugPrint('❌ Error details: ${e.toString()}');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      // Return empty string to trigger fallback
      return '';
    }
  }

  /// Extract text from PDF bytes - Enhanced extraction with better text parsing
  /// Falls back to OCR if standard extraction fails
  Future<String> extractTextFromPDFBytes(Uint8List bytes, String fileName) async {
    try {
      debugPrint('=== STARTING PDF TEXT EXTRACTION ===');
      debugPrint('PDF file: $fileName, Size: ${bytes.length} bytes');
      
      // Step 1: Try OCR first for SAP PDFs (they often have encoding issues)
      try {
        debugPrint('📄 Attempting OCR-based extraction (best for SAP PDFs)...');
        final ocrText = await extractTextFromPDFBytesWithOCR(bytes, fileName);
        if (ocrText.isNotEmpty && ocrText.length > 200) {
          // Check if OCR text looks readable
          final hasReadableContent = RegExp(r'[a-zA-Z]{3,}').hasMatch(ocrText) &&
              (ocrText.toLowerCase().contains('po') ||
               ocrText.toLowerCase().contains('purchase') ||
               ocrText.toLowerCase().contains('order') ||
               RegExp(r'\d{8,}').hasMatch(ocrText)); // Has PO number-like patterns
          
          if (hasReadableContent) {
            debugPrint('✅ OCR extraction successful with readable content');
            return sanitizePdfText(ocrText);
          }
        }
      } catch (e) {
        debugPrint('⚠️ OCR extraction failed, falling back to standard extraction: $e');
      }
      
      // Step 2: Extract text directly from PDF bytes (handles compressed PDFs)
      debugPrint('📄 Step 2: Extracting text directly from PDF structure...');
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
        final result = await _m.generateContent([Content.text(extractionPrompt)])
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
  /// Enhanced to filter out postscript/metadata streams (like pdfplumber extract_text())
  /// Only extracts visible characters, ignores metadata streams
  Future<String> _extractTextFromPDFAlternative(Uint8List bytes, String fileName) async {
    try {
      debugPrint('=== EXTRACTING TEXT FROM PDF BYTES (pdfplumber-style) ===');
      final pdfString = String.fromCharCodes(bytes);
      
      // PRE-FILTER: Remove postscript/metadata streams before extraction
      // This mimics pdfplumber's behavior of ignoring stream data
      String preFiltered = pdfString;
      
      // Remove stream blocks (postscript/metadata)
      preFiltered = preFiltered.replaceAll(RegExp(r'stream\s+.*?endstream', caseSensitive: false, dotAll: true), ' ');
      
      // Remove PDF stream filters
      preFiltered = preFiltered.replaceAll(RegExp(r'/FlateDecode', caseSensitive: false), '');
      preFiltered = preFiltered.replaceAll(RegExp(r'/BitsPerComponent\s+\d+', caseSensitive: false), '');
      preFiltered = preFiltered.replaceAll(RegExp(r'/RunLengthDecode', caseSensitive: false), '');
      
      // Remove SAP metadata patterns
      preFiltered = preFiltered.replaceAll(RegExp(r'\bSAP_WFRT\b', caseSensitive: false), '');
      preFiltered = preFiltered.replaceAll(RegExp(r'\bZMEDRUCK\b', caseSensitive: false), '');
      preFiltered = preFiltered.replaceAll(RegExp(r'\bNetWeaver\b', caseSensitive: false), '');
      preFiltered = preFiltered.replaceAll(RegExp(r'\bVER\s+[\d.]+', caseSensitive: false), '');
      
      final extractedText = StringBuffer();
      final seenText = <String>{};
      
      // Method 1: Extract text from parentheses (most common PDF text format)
      // Look for text in parentheses that contains readable content
      final textPattern = RegExp(r'\(([^)]+)\)', multiLine: true);
      final matches = textPattern.allMatches(preFiltered);
      
      for (final match in matches) {
        final text = match.group(1);
        if (text != null && text.length > 1) {
          // Skip PDF commands, metadata, and corrupted patterns
          if (!text.startsWith('/') && 
              !text.startsWith('\\') &&
              !text.contains('\\x') && 
              !text.contains('FlateDecode') &&
              !text.contains('BitsPerComponent') &&
              !text.contains('RunLengthDecode') &&
              !text.contains('SAP_WFRT') &&
              !text.contains('ZMEDRUCK') &&
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
            
            // Filter out corrupted text patterns (like ];P+ e;*A[Xs)
            if (RegExp(r'[\]\[;P+\s*e;*A\[Xs]{3,}').hasMatch(cleanText)) {
              continue; // Skip corrupted text
            }
            
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
      // Filter out postscript streams first
      final btPattern = RegExp(r'BT\s+(.*?)\s+ET', dotAll: true);
      final btMatches = btPattern.allMatches(preFiltered);
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
      // Look for sequences of printable ASCII characters (visible text only)
      // Filter out corrupted patterns like ];P+ e;*A[Xs
      final asciiPattern = RegExp(r'[A-Za-z0-9\s\.,:;!?@#$%^&*()_+\-=\[\]{}|;"<>?/]{10,}');
      final asciiMatches = asciiPattern.allMatches(preFiltered);
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
            !text.contains('endobj') &&
            !text.contains('FlateDecode') &&
            !text.contains('BitsPerComponent') &&
            !text.contains('RunLengthDecode') &&
            !text.contains('SAP_WFRT') &&
            !RegExp(r'[\]\[;P+\s*e;*A\[Xs]{3,}').hasMatch(text)) { // Skip corrupted patterns
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
        final result = await _m.generateContent([Content.text(prompt)])
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
        final result = await _m.generateContent([Content.text(prompt)]);
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
          'maxOutputTokens': 8192, // Increased for complex documents with many line items
          'temperature': 0.1, // Lower temperature for more consistent extraction
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

      // 5. Extract text from PDF for fallback extraction
      String pdfText = '';
      try {
        pdfText = await extractTextFromPDFBytes(pdfBytes, fileName);
        debugPrint('📄 Extracted PDF text for fallback: ${pdfText.length} characters');
      } catch (e) {
        debugPrint('⚠️ Could not extract PDF text for fallback: $e');
      }
      
      // 6. Parse the valid JSON with PDF text for fallback
      final parsedResult = await _parseSemanticResponse(response, pdfText);
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
        final result = await _j.generateContent([Content.text(prompt)])
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
        final result = await _m.generateContent([Content.text(testPrompt)]);
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
        final result = await _m.generateContent([Content.text(prompt)]);
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
  /// Optimized for SAP-generated Procurement Documents with layout-aware extraction
  /// Specifically designed for Almarai Purchase Order format
  /// PRECISION DATA EXTRACTOR FOR FLUTTER APPLICATION
  String _buildSemanticExtractionPromptForPDF() {
    return '''
You are a precision data extractor for a Flutter application. Your task is to parse the provided Almarai Purchase Order text into a single, valid JSON object.

The text has been extracted using OCR from the PDF pages, so it contains clean, readable business data. Process it carefully following the exact data mapping rules below.

CRITICAL FOR FLUTTER/DART: This text was extracted via OCR to bypass SAP "Identity-H" encoding issues. You MUST:
1. Process the OCR-extracted text as clean business data
2. IGNORE technical metadata: ZMEDRUCK, SAP_WFRT, /FlateDecode, VER 8.00, and similar corrupted text
3. Focus EXCLUSIVELY on business values and readable content
4. Handle multi-line descriptions - merge split text into single strings
5. Extract exact field values as they appear in the document
6. Return ONLY raw JSON object - no markdown, no conversational text, no code blocks

DATA MAPPING RULES (Precision Extraction):

1. poNumber: Extract "PO. No" or "PO. No." and extract the 10-digit number
   - Example: 9500377275
   - Extract the numeric value immediately after the label

2. poDate: Extract "P.O. Date" and convert to YYYY-MM-DD format
   - Example: 28Jan26 → "2026-01-28"
   - Handle SAP date format: DDMMMYY → YYYY-MM-DD

3. vendorName: Extract name from the "Vendor" section
   - Example: AL KAREEM ENTERPRISES LLC
   - Extract the exact company name from the Vendor field

4. customerName: Set as "Almarai Company Drinks Mfg LLC"
   - Always use this exact value for Almarai POs

5. customerAddress: Extract the full "Please deliver to" address
   - Include complete address: KHIA8, Al Taweelah, Abu Dhabi, and any other address components
   - Extract all address lines as a single string

6. totalAmount: Extract the numerical value from "Total Value of this Order" as STRING
   - Example: "900.00" (MUST be a string, not a number)
   - Extract numeric value as a string, remove currency symbols and commas
   - MUST be a string like "900.00" to avoid Flutter type errors

7. currency: Extract from the total section
   - Example: AED
   - Usually found near total amounts or price columns

8. quotationReference: Extract the quotation reference number
   - Look for "Quotation No." or "Quotation Reference N°"
   - Combine both if they exist, otherwise use the single value found
   - Example: ALK25012026-170286

9. lineItems: Create a list. For each item, extract the following fields:
    
    SCAN THE TEXT for rows that start with a numeric Item No (e.g., 10) followed by a 7-digit SAP Code (e.g., 1290441).
    
    EXTRACTION RULES FOR EACH LINE ITEM:
    
    1. itemNo: Extract the numeric Item No
       - Example: 10
       - Extract as numeric value
    
    2. sapCode: Extract the 7-digit SAP Code
       - Example: 1290441
       - Extract as string value
    
    3. description: Cleaned string
       - Capture ALL text between the SAP Code and the Quantity
       - Merge multi-line text into a single string
       - CRITICAL FOR FLUTTER/DART: You MUST escape all double quotes within the description
       - Example: If description is "Glove 8 - S", write it as "Glove 8 - S" (remove quotes) or escape properly
       - Example: If description contains quotes like "Ansell Gloves", escape as "Ansell \\"Gloves\\"" or remove quotes: "Ansell Gloves"
       - This prevents FormatException in jsonDecode() in Flutter/Dart
       - Continue capturing until you hit a number representing the quantity
    
    4. quantity: Numerical value (as double, not string)
       - Example: 5.00
       - Extract the decimal number only
       - MUST be a numeric value (double), not a string like "5.00"
    
    5. unitPrice: Numerical value (as double, not string)
       - Example: 180.00
       - Extract numeric value only, remove currency symbols
       - MUST be a numeric value (double), not a string
    
    VALIDATION REQUIREMENT:
    - Ensure (quantity * unitPrice) == totalPrice for each line item
    - If they don't match, use the calculated value (quantity * unitPrice) as totalPrice
    - All numeric fields (quantity, unitPrice, totalPrice) MUST be doubles, not strings
    
    5. VISUAL ROW ALIGNMENT (LIKE OCR):
       - Use visual layout and coordinate proximity to group text blocks into logical rows
       - Extract ONLY visible characters on the page (read as a human would see it)
       - Group text by visual proximity: items on the same horizontal line (similar y-coordinates) belong together
       - All fields from the same visual row MUST be grouped together
       - If data appears fragmented, use your internal logic to re-align columns based on the Almarai table structure
    
    6. CONSTRAINT: Output ONLY clean JSON. If an item row is found but data is fragmented, use your internal logic to re-align the columns based on the Almarai table structure.
    
STRICT REQUIREMENTS:

1. Skip Metadata: Ignore strings like ZMEDRUCK, SAP_WFRT, or /FlateDecode
   - Do NOT include PDF metadata: endstream, FlateDecode, obj, endobj, xref, trailer
   - Do NOT include sequences of special characters that look like font mapping errors
   - Only extract readable business data with actual content

2. Validation: Ensure (quantity * unitPrice) == totalPrice for each line item
   - If they don't match, recalculate totalPrice as (quantity * unitPrice)

CRITICAL CONSTRAINTS FOR VALID jsonDecode():

1. No Explanations: Return ONLY the JSON object. No markdown, no conversational text, no code blocks.

2. Escape Quotes: CRITICAL - You MUST escape ALL double quotes within ALL string values
   - The PO description contains brand names and dimensions with quotes (e.g., "Ansell", "8 - S")
   - Example: If description is "Ansell HyFlex Black General Purpose Nylon Polyurethane-Coated Reusable Gloves 8 - S", escape ALL quotes
   - Write as: "Ansell HyFlex Black General Purpose Nylon Polyurethane-Coated Reusable Gloves 8 - S" (remove quotes) OR escape as "Ansell \\"HyFlex\\" Black General Purpose Nylon Polyurethane-Coated Reusable Gloves 8 - S"
   - This applies to ALL string fields: description, notes, terms, customerAddress, etc.
   - If any field contains quotes like "Almarai Payment Guidelines", escape them: "Almarai \\"Payment Guidelines\\"" OR remove the quotes entirely

3. Sanitize Text: Do NOT include phrases like "Please refer 'Almarai Payment Guidelines'" inside JSON values unless they are part of a specific field
   - Keep notes/terms fields concise and relevant
   - If notes field would contain problematic text with unescaped quotes, set notes to null instead
   - Avoid including long boilerplate text that contains unescaped quotes

4. Null Safety: If a field like expiryDate is missing, return null, not "Unknown" or empty string

5. Data Types: CRITICAL FOR FLUTTER TYPE SAFETY
   - totalAmount must be a STRING (like "900.00"), not a number, to avoid Flutter type errors
   - quantity, unitPrice, and totalPrice in lineItems must be STRINGS (like "5.00", "180.00", "900.00"), not numbers
   - itemNo must be a STRING (like "10"), not a number
   - All numeric-looking fields must be quoted strings to match Flutter model expectations

6. The JSON must be parseable by jsonDecode() in Flutter/Dart without any FormatException
    
    VALIDATE TOTALS:
    - Cross-reference the "Total Price" of line items with the "Total Value of this Order"
    - For multi-page documents: Aggregate data from all pages
    - Ensure the total value from Page 2 matches the sum of line items from Page 1
    
    DATA INTEGRITY:
    - Convert all numeric strings to proper float values (quantity, unitPrice, total)
    - Ensure quantity, unitPrice, and total are numeric (not strings) for proper calculations
    - If total is missing, calculate it as quantity × unitPrice (both must be numeric)
    - Handle decimal values correctly (e.g., "180.00" → 180.0, "5.5" → 5.5)
    
    EXTRACTION RULES:
    - Look for tables with columns like: "Item No", "Description", "SAP Code", "Part Number", "Vendor Part No", "Quantity", "Qty", "UOM", "Unit", "Unit Price", "Total Price", "Total"
    - Extract EVERY row from the table, even if some fields are missing
    - For each item, extract:
      * itemName: The main product description (from "Description" column - preserve full text including technical specs, merge multi-line text)
      * itemCode: Item No, SAP Code, Vendor Part No, Part Number, or Material Code (prioritize Item No, then SAP Code)
      * description: Full detailed description including technical specifications (e.g., "Ansell HyFlex Black General Purpose...")
      * manufacturerPartNo: Manufacturer Part No or Vendor Part No (CRITICAL - may be on separate line, merge using y-coordinates)
      * quantity: Numeric quantity value (convert string to float, handle null as 0.0)
      * unit: Unit of measure (BAG, PCS, EA, KG, etc. from "UOM" or "Unit" column, default to "pcs" if null)
      * unitPrice: Unit price (numeric value, remove currency symbols, convert string to float, handle null as 0.0)
      * total: Total price for the line item (numeric value, remove currency symbols, convert string to float, calculate if null)
    - If total is missing or 0, calculate it as quantity × unitPrice (ensure both are numeric)
    - Extract from ANY table format, even if columns are misaligned or have different names
    - DO NOT skip line items - extract ALL items visible in the table
    - Preserve row integrity - all fields from the same visual row must stay together

CRITICAL: Return ONLY a raw JSON object. Do not include any conversational text, backticks, or markdown formatting.

RETURN DATA STRICTLY IN THIS JSON FORMAT (NO MARKDOWN, NO CODE BLOCKS, NO EXPLANATIONS):

{
  "isValid": true,
  "poData": {
    "poNumber": "9500377275",
    "quotationReference": "ALK25012026-170286",
    "poDate": "2026-01-28",
    "expiryDate": "2026-02-02",
    "vendorName": "AL KAREEM ENTERPRISES LLC",
    "customerName": "Almarai Company Drinks Mfg LLC",
    "customerAddress": "KHIA8, plot91, Al Taweelah, KIZAD A, Abu Dhabi, Abu Dhabi 137510",
    "customerEmail": "Rekadharshini.Karuppusamy@almarai.com",
    "totalAmount": "900.00",
    "currency": "AED",
    "terms": "30 DAYS AFTER INVOICE",
    "notes": null,
    "lineItems": [
      {
        "itemNo": "10",
        "sapCode": "1290441",
        "itemName": "GLOVES HYFLEXULTRA-LITE PU GLV8 -ANSELL",
        "itemCode": "1290441",
        "description": "Ansell HyFlex Black General Purpose Nylon Polyurethane-Coated Reusable Gloves 8 - S RS Stock No. 713-4264 Brand Ansell Mfr. Part No. 11-618/08",
        "quantity": "5.00",
        "uom": "BAG",
        "unit": "BAG",
        "unitPrice": "180.00",
        "totalPrice": "900.00",
        "total": "900.00"
      }
    ]
  },
  "summary": "2-3 sentence English summary"
}

CRITICAL JSON FORMATTING REQUIREMENTS:
- Return ONLY the raw JSON object - no markdown backticks (```json), no conversational filler text
- Ensure every single key and value is wrapped in double quotes
- All numeric-looking fields (itemNo, quantity, unitPrice, totalPrice, totalAmount) MUST be strings, not numbers
- Remove ALL newline characters (\\n) from description field
- Escape all internal double quotes in string values OR remove them
- Ensure no trailing commas at the end of the lineItems array
- The JSON must be parseable by jsonDecode() in Flutter/Dart without any FormatException or type errors

CRITICAL RULES - YOU MUST FOLLOW THESE EXACTLY:

1. MANDATORY EXTRACTION - DO NOT RETURN NULL:
   - You MUST extract data from the PDF. Returning null for all fields is NOT ACCEPTABLE.
   - If you see ANY text that resembles a PO number, date, company name, or line item, you MUST extract it.
   - Scan the ENTIRE document visually - look at every page, every section, every table.
   - If a field label exists (like "PO. No."), the value MUST be nearby - find it and extract it.

2. NOTES FIELD HANDLING (CRITICAL FOR JSON VALIDITY):
   - If notes would contain text with unescaped quotes (like "Almarai Payment Guidelines" or "Please refer 'Almarai Payment Guidelines'"), set notes to null
   - Do NOT include long boilerplate text that contains quotes in the notes field
   - Keep notes concise and relevant, or set to null if problematic

3. FIELD EXTRACTION PRIORITY:
   - poNumber: MANDATORY - Search for "PO. No.", "PO No.", "PO Number", "Order No", "PO #" - extract the numeric value you see
   - poDate: MANDATORY - Search for "P.O. Date", "PO Date", "Date", "Order Date" - extract and convert to YYYY-MM-DD
   - vendorName: MANDATORY - Search for "Vendor:", "Vendor Name", "Supplier" - extract the company name
   - customerName: MANDATORY - Search for "Please deliver to:", "Buyer/Consignee", "Ship To", "Customer Name" - extract the company name
   - totalAmount: MANDATORY - Search for "Total Value of this Order", "Grand Total", "Total Amount", "Total" - extract the numeric value
   - lineItems: CRITICAL - You MUST find and extract ALL line items from the table. Empty array [] means FAILURE.

3. LINE ITEMS EXTRACTION (MOST IMPORTANT):
   - Look for ANY table structure in the document
   - Look for rows with numbers, descriptions, quantities, and prices
   - Even if the table format is unusual, extract what you see
   - Minimum requirement: Extract at least the item description and quantity
   - If you see a table with multiple rows, each row is likely a line item

4. PROCESSING INSTRUCTIONS:
   - Process the PDF visually - read it like a human would see it on screen
   - The PDF is provided as binary data - use your vision capabilities to read it
   - Ignore corrupted text, metadata, and technical information
   - Focus ONLY on readable business data

5. OUTPUT FORMAT:
   - Return ONLY the JSON object - no markdown, no code blocks, no explanations
   - Use the exact JSON structure provided below
   - If a field cannot be found after thorough search, use null (but this should be RARE)

REMEMBER: Your primary goal is to EXTRACT DATA. If you return all null values, you have not completed your task.
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
  /// pdfText is optional and used for fallback extraction if line items are missing
  Future<Map<String, dynamic>> _parseSemanticResponse(String response, [String pdfText = '']) async {
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
      String summary = jsonData['summary'] as String? ?? 'Purchase Order extracted successfully.';
      
      // CRITICAL: If all fields are null, try fallback extraction from PDF text
      if (poDataJson != null) {
        final poNumber = poDataJson['poNumber'];
        final poDate = poDataJson['poDate'];
        final customerName = poDataJson['customerName'];
        final vendorName = poDataJson['vendorName'];
        final totalAmount = poDataJson['totalAmount'];
        final lineItems = poDataJson['lineItems'] as List?;
        
        final allFieldsNull = (poNumber == null || poNumber == 'null' || poNumber == '') &&
                           (poDate == null || poDate == 'null' || poDate == '') &&
                           (customerName == null || customerName == 'null' || customerName == '') &&
                           (vendorName == null || vendorName == 'null' || vendorName == '') &&
                           (totalAmount == null || totalAmount == 0.0) &&
                           (lineItems == null || lineItems.isEmpty);
        
        if (allFieldsNull) {
          debugPrint('⚠️ WARNING: All fields are null in AI response. Attempting fallback extraction...');
          debugPrint('📄 PDF text length: ${pdfText.length}');
          
          // If PDF text is also empty, log a critical error
          if (pdfText.isEmpty || pdfText.length < 50) {
            debugPrint('❌ CRITICAL: PDF text extraction also failed. PDF may be corrupted or image-based.');
            debugPrint('❌ This suggests the PDF cannot be read by standard text extraction methods.');
          }
          
          // Extract PO Number
          if (poNumber == null || poNumber == 'null' || poNumber == '') {
            final poMatch = RegExp(r'PO\.?\s*No\.?[:\s]*(\d{8,})', caseSensitive: false).firstMatch(pdfText);
            if (poMatch != null) {
              poDataJson['poNumber'] = poMatch.group(1);
              debugPrint('✅ Fallback extracted poNumber: ${poMatch.group(1)}');
            }
          }
          
          // Extract PO Date
          if (poDate == null || poDate == 'null' || poDate == '') {
            final dateMatch = RegExp(r'P\.?O\.?\s*Date[:\s]*(\d{1,2}[A-Za-z]{3}\d{2,4}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})', caseSensitive: false).firstMatch(pdfText);
            if (dateMatch != null) {
              final dateStr = dateMatch.group(1);
              if (dateStr != null) {
                final parsedDate = _parseDate(dateStr);
                if (parsedDate != null) {
                  poDataJson['poDate'] = parsedDate;
                  debugPrint('✅ Fallback extracted poDate: $parsedDate');
                }
              }
            }
          }
          
          // Extract Customer Name
          if (customerName == null || customerName == 'null' || customerName == '') {
            final customerMatch = RegExp(r'Please\s+deliver\s+to[:\s]+([A-Z][A-Za-z\s&]+(?:Company|Corp|LLC|Ltd)?)', caseSensitive: false).firstMatch(pdfText);
            if (customerMatch != null) {
              poDataJson['customerName'] = customerMatch.group(1)?.trim();
              debugPrint('✅ Fallback extracted customerName: ${customerMatch.group(1)}');
            }
          }
          
          // Extract Vendor Name
          if (vendorName == null || vendorName == 'null' || vendorName == '') {
            final vendorMatch = RegExp(r'Vendor[:\s]+([A-Z][A-Za-z\s&]+(?:Company|Corp|LLC|Ltd|ENTERPRISES)?)', caseSensitive: false).firstMatch(pdfText);
            if (vendorMatch != null) {
              poDataJson['vendorName'] = vendorMatch.group(1)?.trim();
              debugPrint('✅ Fallback extracted vendorName: ${vendorMatch.group(1)}');
            }
          }
          
          // Extract Total Amount
          if (totalAmount == null || totalAmount == 0.0) {
            final totalMatch = RegExp(r'Total\s+Value\s+of\s+this\s+Order[:\s]+(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(pdfText);
            if (totalMatch != null) {
              poDataJson['totalAmount'] = double.tryParse(totalMatch.group(1) ?? '0') ?? 0.0;
              debugPrint('✅ Fallback extracted totalAmount: ${poDataJson['totalAmount']}');
            } else {
              // Try alternative patterns
              final altMatch = RegExp(r'Total[:\s]+(\d+(?:\.\d+)?)\s*(?:AED|USD|INR)?', caseSensitive: false).firstMatch(pdfText);
              if (altMatch != null) {
                poDataJson['totalAmount'] = double.tryParse(altMatch.group(1) ?? '0') ?? 0.0;
                debugPrint('✅ Fallback extracted totalAmount (alt pattern): ${poDataJson['totalAmount']}');
              }
            }
          }
          
          // Log summary of fallback extraction
          final extractedCount = [
            poDataJson['poNumber'],
            poDataJson['poDate'],
            poDataJson['customerName'],
            poDataJson['vendorName'],
            poDataJson['totalAmount']
          ].where((v) => v != null && v != 'null' && v != '' && v != 0.0).length;
          
          debugPrint('📊 Fallback extraction summary: $extractedCount fields extracted');
        }
      }
      
      PurchaseOrder? poData;
      if (poDataJson != null && poDataJson.isNotEmpty) {
        try {
          // Convert N/A to null, handle null values gracefully
          final cleanedPoData = Map<String, dynamic>.from(poDataJson);
          
          // Handle N/A values and null strings - but preserve actual values
          if (cleanedPoData['poNumber'] == 'N/A') {
            cleanedPoData['poNumber'] = null;
          }
          // Ensure quotationReference is preserved
          if (cleanedPoData['quotationReference'] == 'N/A' || cleanedPoData['quotationReference'] == null) {
            cleanedPoData['quotationReference'] = null;
          } else {
            debugPrint('✅ Preserving quotationReference: ${cleanedPoData['quotationReference']}');
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
          // Ensure customerAddress is preserved
          if (cleanedPoData['customerAddress'] != null && cleanedPoData['customerAddress'].toString().trim().isNotEmpty) {
            debugPrint('✅ Preserving customerAddress');
          }
          // Ensure customerEmail is preserved
          if (cleanedPoData['customerEmail'] != null && cleanedPoData['customerEmail'].toString().trim().isNotEmpty) {
            debugPrint('✅ Preserving customerEmail: ${cleanedPoData['customerEmail']}');
          }
          
          // Handle null numeric fields - but preserve actual values
          if (cleanedPoData['totalAmount'] == null) {
            cleanedPoData['totalAmount'] = 0.0;
          } else if (cleanedPoData['totalAmount'] == 0.0) {
            // Keep 0.0 if it's already 0.0
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
                // CRITICAL: Use _convertToFloat() instead of direct casting to handle strings
                final itemName = (cleanedItem['itemName'] as String? ?? '').trim();
                final description = (cleanedItem['description'] as String? ?? '').trim();
                final currentUnitPrice = _convertToFloat(cleanedItem['unitPrice']);
                
                if (currentUnitPrice == 0.0 && (itemName.isNotEmpty || description.isNotEmpty)) {
                  // Try fuzzy matching against catalog
                  final matchedPrice = catalogService.matchItemPrice(itemName, description: description);
                  if (matchedPrice > 0.0) {
                    cleanedItem['unitPrice'] = matchedPrice;
                    debugPrint('✅ Fuzzy matched: "$itemName" -> ${matchedPrice} AED');
                  }
                }
                
                // Ensure unitPrice is set (use matched price or keep existing)
                // CRITICAL: Convert to double to ensure type safety
                if (cleanedItem['unitPrice'] == null) {
                  cleanedItem['unitPrice'] = 0.0;
                } else {
                  cleanedItem['unitPrice'] = _convertToFloat(cleanedItem['unitPrice']);
                }
                
                // Ensure quantity is converted to double
                if (cleanedItem['quantity'] == null) {
                  cleanedItem['quantity'] = 0.0;
                } else {
                  cleanedItem['quantity'] = _convertToFloat(cleanedItem['quantity']);
                }
                
                // Calculate total if missing
                if (cleanedItem['total'] == null) {
                  final qty = _convertToFloat(cleanedItem['quantity']);
                  final price = _convertToFloat(cleanedItem['unitPrice']);
                  cleanedItem['total'] = qty * price;
                } else {
                  // Ensure total is also converted to double
                  cleanedItem['total'] = _convertToFloat(cleanedItem['total']);
                }
                
                cleanedItems.add(cleanedItem);
              }
            }
            cleanedPoData['lineItems'] = cleanedItems;
          }
          
          // CRITICAL: Ensure totalAmount is also converted to double (not string)
          if (cleanedPoData['totalAmount'] != null) {
            cleanedPoData['totalAmount'] = _convertToFloat(cleanedPoData['totalAmount']);
          }
          
          final jsonString = json.encode(cleanedPoData);
          
          // Check if line items are missing and we have PDF text for fallback
          final hasLineItems = cleanedPoData['lineItems'] != null && 
                               cleanedPoData['lineItems'] is List &&
                               (cleanedPoData['lineItems'] as List).isNotEmpty;
          
          if (!hasLineItems && pdfText.isNotEmpty) {
            debugPrint('⚠️ No line items found in semantic response, attempting fallback extraction from PDF text...');
            // Try to extract line items from PDF text
            poData = _parseExtractedData(jsonString, pdfText);
          } else {
            poData = _parseExtractedData(jsonString, pdfText.isNotEmpty ? pdfText : '');
          }
          
          // Final check - if still no line items, try one more aggressive extraction
          if (poData.lineItems.isEmpty && pdfText.isNotEmpty) {
            debugPrint('⚠️ Still no line items after parsing, attempting aggressive fallback extraction...');
            try {
              // Try direct extraction from PDF text as last resort
              final fallbackPO = await extractPOData(pdfText);
              if (fallbackPO.lineItems.isNotEmpty) {
                debugPrint('✅ Found ${fallbackPO.lineItems.length} line items using fallback extraction!');
                // Merge line items into the existing PO
                poData = poData.copyWith(
                  lineItems: fallbackPO.lineItems,
                  totalAmount: fallbackPO.totalAmount > 0 ? fallbackPO.totalAmount : poData.totalAmount,
                );
              }
            } catch (e) {
              debugPrint('⚠️ Fallback extraction also failed: $e');
            }
          }
          
          debugPrint('✅ Successfully parsed PO data from semantic extraction');
          if (poData != null) {
            debugPrint('✅ Line items count: ${poData.lineItems.length}');
            if (poData.lineItems.isNotEmpty) {
              debugPrint('✅ First line item: ${poData.lineItems.first.itemName}, Qty: ${poData.lineItems.first.quantity}, Price: ${poData.lineItems.first.unitPrice}');
            }
          }
        } catch (e, stackTrace) {
          debugPrint('❌ Error parsing extracted data: $e');
          debugPrint('❌ Stack trace: $stackTrace');
          debugPrint('❌ This error occurred while converting JSON to PurchaseOrder object.');
          debugPrint('❌ The AI response may have invalid data types or missing required fields.');
          poData = null;
          // Update summary to include error information for better debugging
          if (e.toString().contains('type') && e.toString().contains('subtype')) {
            summary = 'Data type error during parsing: ${e.toString()}. This usually means the AI returned data in an unexpected format. Please try again.';
          } else {
            summary = 'Failed to parse extracted data: ${e.toString()}. ${summary.isNotEmpty && !summary.contains("Failed to parse") ? "Original summary: $summary" : "Please check the PDF format and try again."}';
          }
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

    // Step 1: Remove markdown code blocks (CRITICAL for Flutter - prevents FormatException)
    // Remove all markdown formatting including backticks
    cleaned = cleaned.replaceAll(RegExp(r'```json\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```json'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^```', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```$', multiLine: true), '');
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
    
    // Step 2.5: CRITICAL - Escape unescaped quotes within string values
    // This prevents FormatException when descriptions/notes contain quotes like "Ansell" or "Almarai Payment Guidelines"
    // Process JSON character by character to properly identify and escape quotes within string values
    cleaned = _escapeQuotesInStringValues(cleaned);

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
    
    // Step 4b: Add missing closing braces/brackets - FIX: Only add what's needed, don't over-add
    // First, check if there are extra closing braces (like "}}"}})
    // Remove any trailing extra closing braces/brackets before counting
    String tempJson = completedJson.trimRight();
    while (tempJson.endsWith('}') || tempJson.endsWith(']')) {
      final lastChar = tempJson[tempJson.length - 1];
      tempJson = tempJson.substring(0, tempJson.length - 1).trimRight();
      if (lastChar == '}') {
        closeBraces--; // Adjust count
      } else {
        closeBrackets--; // Adjust count
      }
    }
    completedJson = tempJson;
    
    // Re-count braces after cleaning
    openBraces = 0;
    closeBraces = 0;
    openBrackets = 0;
    closeBrackets = 0;
    inString = false;
    escapeNext = false;
    
    for (int i = 0; i < completedJson.length; i++) {
      final char = completedJson[i];
      
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
    
    // Now add only the missing closing braces/brackets
    if (openBraces > closeBraces) {
      // Remove trailing comma if present before adding closing brace
      completedJson = completedJson.replaceAll(RegExp(r',\s*$'), '');
      // Add missing closing braces - but ensure we don't add too many
      final missingBraces = openBraces - closeBraces;
      for (int i = 0; i < missingBraces; i++) {
        completedJson += '}';
      }
      debugPrint('✅ Completed JSON: Added $missingBraces closing brace(s)');
    }
    
    if (openBrackets > closeBrackets) {
      // Remove trailing comma if present before adding closing bracket
      completedJson = completedJson.replaceAll(RegExp(r',\s*$'), '');
      // Add missing closing brackets
      final missingBrackets = openBrackets - closeBrackets;
      for (int i = 0; i < missingBrackets; i++) {
        completedJson += ']';
      }
      debugPrint('✅ Completed JSON: Added $missingBrackets closing bracket(s)');
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
  
  /// Escape unescaped quotes within string values in JSON
  /// This prevents FormatException when string values contain quotes like "Ansell" or "Almarai Payment Guidelines"
  String _escapeQuotesInStringValues(String json) {
    final result = StringBuffer();
    bool inString = false;
    bool escapeNext = false;
    
    for (int i = 0; i < json.length; i++) {
      final char = json[i];
      
      if (escapeNext) {
        result.write(char);
        escapeNext = false;
        continue;
      }
      
      if (char == '\\') {
        result.write(char);
        escapeNext = true;
        continue;
      }
      
      if (char == '"') {
        if (inString) {
          // We're inside a string value - check if this quote should be escaped
          // Look ahead to see if this is the end of the string value
          if (i < json.length - 1) {
            final nextChar = json[i + 1];
            // If next char is not :, }, ], ,, or whitespace, this quote is part of the string content
            if (nextChar != ':' && nextChar != '}' && nextChar != ']' && nextChar != ',' && 
                nextChar != '\n' && nextChar != '\r' && nextChar != ' ' && nextChar != '\t') {
              // This quote is inside the string value and needs to be escaped
              result.write('\\"');
              continue;
            }
          }
          // This is the end of a string value
          inString = false;
        } else {
          // This is the start of a string
          inString = true;
        }
        result.write(char);
        continue;
      }
      
      result.write(char);
    }
    
    return result.toString();
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
   - PO Number: Look for "PO Number:", "PO:", "PO #", "Order No", "Purchase Order Number", "PO No."
   - Quotation Reference/Quote No: Look for "Quotation Number:", "Quotation:", "Quote No:", "Quote #:", "QTN:", "Quotation Reference:", "Ref Quotation:", "QUOTATION REFERENCE NO", "Quotation Reference N°"
   - Vendor Name: Look for "Vendor Name:", "Vendor:", "Supplier Name:", "Supplier:", "Customer Name:", "Customer:", "Bill To:", "Ship To:"
   - PO Date: Look for "PO Date:", "Date:", "Order Date:", "Issue Date:", "P.O. Date" (convert to YYYY-MM-DD format)
     * Handle formats like "28Jan26" → "2026-01-28", "Jan 28, 2026" → "2026-01-28"
   - Expiry Date/Validity: Look for "Expiry Date:", "Valid Until:", "Expiration Date:", "Validity To:", "Validity Date:" (convert to YYYY-MM-DD format or null)
   - Customer Address: Look for "Address:", "Bill To Address:", "Ship To Address:", "Please deliver to:", "Delivery Address:", "Shipping Address:"
   - Customer Email: Look for "Email:", "Email Address:", "Contact Email:", "Email ID:", "Buyer Email:"
   - Total Amount: Look for "Grand Total:", "Total Amount:", "Total:", "Amount Due:", "Total Price AED", "Total AED" (extract numeric value only)
   - Currency: Look for currency code (AED, USD, INR, EUR, etc.) from amount fields
   - Line Items: CRITICAL - Extract ALL line items from tables using ROW ANCHORING. This is MANDATORY.
3. For line items: Extract from table with ROW ANCHORING to preserve data integrity
   
   ROW ANCHORING RULES:
   - Group all fields from the same visual row together (Item No, Description, SAP Code, Vendor Part No, Qty, Unit Price, Total)
   - Preserve technical specifications in descriptions (e.g., "Ansell HyFlex Black General Purpose...")
   - DO NOT split multi-line descriptions across different rows
   - Ensure all numeric values are properly converted to floats (not strings) for calculations
   
   SAP/ALMARAI FORMAT COLUMNS:
   - Item No: Extract as itemCode (primary identifier)
   - SAP Code: Use as itemCode if Item No is missing
   - Vendor Part No: Additional identifier if available
   - Description: Full product description including technical specs (preserve complete text)
   - Quantity/Qty: Convert to numeric float value
   - UOM/Unit: Unit of measure (BAG, PCS, EA, KG, etc.)
   - Unit Price: Convert to numeric float value (remove currency symbols)
   - Total/Total Price: Convert to numeric float value (remove currency symbols)
   
   EXTRACTION INSTRUCTIONS:
   - Extract ALL rows from the table, even if some fields are missing
   - Use Description column for itemName (main product name - preserve full text)
   - Use Item No as primary itemCode, fallback to SAP Code, then Vendor Part No, then Part Number
   - Extract full description text for each item (may span multiple lines - keep anchored to row)
   - Use Qty/Quantity column for quantity (convert string to numeric float)
   - Use UOM/Unit column for unit (BAG, PCS, EA, KG, etc.)
   - Use Unit Price column for unitPrice (convert string to numeric float, remove currency symbols)
   - Use Total/Total Price column for total (convert string to numeric float, remove currency symbols)
   - If total is missing or 0, calculate it as quantity × unitPrice (both must be numeric floats)
   - DO NOT skip any items - extract ALL visible items in the table
   - DATA INTEGRITY: Ensure all numeric fields (quantity, unitPrice, total) are proper floats, not strings
4. For dates: Convert to YYYY-MM-DD format
   - "28Jan26" → "2026-01-28"
   - "22 November 2025" → "2025-11-22"
   - "November 22, 2025" → "2025-11-22"
   - "02Feb26" → "2026-02-02"
5. For amounts: Extract ONLY the numeric value, remove currency symbols and commas
   - "12127.50 AED" → 12127.50
   - "1,127.50" → 1127.50
   - "900.00" → 900.00
6. DO NOT use sample data, test data, or placeholder values
7. If a field is not found, use null (not "N/A" or "Unknown")
8. LINE ITEMS ARE MANDATORY - If lineItems array is empty, you have failed. Look more carefully for item tables.

Return ONLY valid JSON (no markdown, no code blocks, no explanations):
{
  "poNumber": "exact PO number from document or null",
  "poDate": "date in YYYY-MM-DD format or null",
  "expiryDate": "date in YYYY-MM-DD format or null",
  "quotationReference": "quotation number or reference if found in document, else null",
  "vendorName": "vendor/supplier/customer name from document or null",
  "customerAddress": "complete address if found, else null",
  "customerEmail": "email if found, else null",
  "totalAmount": numeric_value_only,
  "currency": "currency code (AED, INR, USD, EUR, etc.) if found, else null",
  "lineItems": [
    {
      "itemName": "description from table (REQUIRED)",
      "itemCode": "part number/SAP code from table or null",
      "description": "full description text for the item or null",
      "quantity": numeric_value (REQUIRED),
      "unit": "BAG/PCS/EA/etc (REQUIRED)",
      "unitPrice": numeric_value (REQUIRED),
      "total": numeric_value (REQUIRED, calculate if missing)
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

  /// Convert value to float with proper handling of strings, currency symbols, and formatting
  /// Ensures data integrity for calculations (Total AED, etc.)
  /// CRITICAL: This function MUST handle both string and numeric types to prevent type errors
  double _convertToFloat(dynamic value) {
    if (value == null) return 0.0;
    
    // If already a number, convert directly
    if (value is num) {
      return value.toDouble();
    }
    
    // If string, clean and parse
    if (value is String) {
      // Handle empty string or "null" string
      if (value.isEmpty || value.trim().toLowerCase() == 'null') return 0.0;
      
      // Remove currency symbols, commas, and other non-numeric characters except decimal point
      String cleaned = value
          .replaceAll(RegExp(r'[^\d.]'), '') // Remove everything except digits and decimal point
          .trim();
      
      // Handle empty string after cleaning
      if (cleaned.isEmpty) return 0.0;
      
      // Parse to double
      final parsed = double.tryParse(cleaned);
      if (parsed != null) {
        return parsed;
      }
      
      // Try to handle cases like "180.00 AED" or "1,127.50"
      // Remove commas and try again
      cleaned = cleaned.replaceAll(',', '');
      final parsed2 = double.tryParse(cleaned);
      if (parsed2 != null) {
        return parsed2;
      }
      
      // Last resort: try parsing the original string directly
      final directParse = double.tryParse(value.trim());
      return directParse ?? 0.0;
    }
    
    // Fallback: try to convert to string and parse
    try {
      final stringValue = value.toString();
      if (stringValue.isEmpty || stringValue.trim().toLowerCase() == 'null') return 0.0;
      final cleaned = stringValue.replaceAll(RegExp(r'[^\d.]'), '').replaceAll(',', '');
      if (cleaned.isEmpty) return 0.0;
      return double.tryParse(cleaned) ?? 0.0;
    } catch (e) {
      debugPrint('⚠️ Error converting to float: $value (type: ${value.runtimeType}), error: $e');
      return 0.0;
    }
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
            // SAP PDF FIELD MAPPING: Extract exact fields as specified
            // itemNo and sapCode are primary identifiers
            // CRITICAL: Handle both string and int types for itemNo (Flutter expects String)
            dynamic itemNoRaw = item['itemNo'] ?? 
                          item['itemNumber'] ?? 
                          item['item_no'];
            // Convert to string if it's a number (to avoid Flutter type errors)
            final itemNo = itemNoRaw is String ? itemNoRaw : (itemNoRaw is num ? itemNoRaw.toString() : null);
            
            final sapCode = item['sapCode'] ?? 
                           item['SAPCode'] ?? 
                           item['sap_code'] ??
                           item['materialCode'] ??
                           item['material_code'];
            
            // Handle different field name variations for itemName
            String itemName = item['itemName'] ?? 
                           item['name'] ?? 
                           item['description'] ?? 
                           item['item'] ?? 
                           item['product'] ?? '';
            
            // Remove extra newlines from itemName (SAP PDFs often have excessive line breaks)
            if (itemName.isNotEmpty) {
              itemName = itemName.replaceAll(RegExp(r'\n\s*\n+'), ' ').trim();
            }
            
            // itemCode: Use itemNo if available, else sapCode
            final itemCode = itemNo ?? 
                           sapCode ??
                           item['itemCode'] ?? 
                           item['code'] ?? 
                           item['partNumber'] ?? 
                           item['sku'] ?? 
                           item['partNo'];
            
            // description: Full description, remove ALL newlines and escape quotes
            String description = item['description'] ?? 
                               item['details'] ?? 
                               item['itemDescription'] ?? '';
            
            // CRITICAL: Remove ALL newline characters from description (\\n, \\r, etc.)
            if (description.isNotEmpty) {
              description = description
                  .replaceAll('\n', ' ')  // Remove all newlines
                  .replaceAll('\r', ' ')  // Remove carriage returns
                  .replaceAll(RegExp(r'\s+'), ' ')  // Normalize whitespace
                  .trim();
              // Also escape any remaining quotes that might cause JSON errors
              description = description.replaceAll('"', '\\"');
            }
            
            // Extract quantity - handle different field names with proper float conversion
            // CRITICAL: AI may return as string "5.00" or number 5.00 - always convert to double
            double quantity = 0.0;
            if (item['quantity'] != null) {
              quantity = _convertToFloat(item['quantity']);
              debugPrint('📊 Quantity extracted: ${item['quantity']} (type: ${item['quantity'].runtimeType}) -> $quantity');
            } else if (item['qty'] != null) {
              quantity = _convertToFloat(item['qty']);
              debugPrint('📊 Quantity extracted (qty): ${item['qty']} (type: ${item['qty'].runtimeType}) -> $quantity');
            }
            
            // uom: Extract from uom field (SAP format)
            final uom = item['uom'] ?? 
                       item['UOM'] ??
                       item['unit'] ?? 
                       item['unitOfMeasure'] ?? 
                       'pcs';
            
            // unit: Same as uom (for compatibility)
            final unit = uom;
            
            // Extract unit price with proper float conversion (DATA INTEGRITY)
            // CRITICAL: AI may return as string "1.88" or number 1.88 - always convert to double
            double unitPrice = 0.0;
            if (item['unitPrice'] != null) {
              unitPrice = _convertToFloat(item['unitPrice']);
              debugPrint('💰 UnitPrice extracted: ${item['unitPrice']} (type: ${item['unitPrice'].runtimeType}) -> $unitPrice');
            } else if (item['price'] != null) {
              unitPrice = _convertToFloat(item['price']);
              debugPrint('💰 UnitPrice extracted (price): ${item['price']} (type: ${item['price'].runtimeType}) -> $unitPrice');
            } else if (item['unitPriceAED'] != null) {
              unitPrice = _convertToFloat(item['unitPriceAED']);
              debugPrint('💰 UnitPrice extracted (unitPriceAED): ${item['unitPriceAED']} (type: ${item['unitPriceAED'].runtimeType}) -> $unitPrice');
            }
            
            // Extract totalPrice (SAP format) with proper float conversion (DATA INTEGRITY)
            // CRITICAL: AI may return as string "900.00" or number 900.00 - always convert to double
            double total = 0.0;
            if (item['totalPrice'] != null) {
              total = _convertToFloat(item['totalPrice']);
              debugPrint('💵 TotalPrice extracted: ${item['totalPrice']} (type: ${item['totalPrice'].runtimeType}) -> $total');
            } else if (item['total'] != null) {
              total = _convertToFloat(item['total']);
              debugPrint('💵 TotalPrice extracted (total): ${item['total']} (type: ${item['total'].runtimeType}) -> $total');
            } else if (item['lineTotal'] != null) {
              total = _convertToFloat(item['lineTotal']);
              debugPrint('💵 TotalPrice extracted (lineTotal): ${item['lineTotal']} (type: ${item['lineTotal'].runtimeType}) -> $total');
            } else if (quantity > 0 && unitPrice > 0) {
              // Calculate if not provided (ensure both are numeric)
              total = quantity * unitPrice;
              debugPrint('💵 TotalPrice calculated: $quantity * $unitPrice = $total');
            }
            
            // ROW ANCHORING: Ensure description includes technical specs
            // If description is missing but itemName has technical details, use itemName as description
            String finalDescription = description ?? '';
            if (finalDescription.isEmpty && itemName.isNotEmpty) {
              // Check if itemName contains technical specs (long descriptions, part numbers, etc.)
              if (itemName.length > 30 || itemName.contains(RegExp(r'[A-Z]{2,}\s+[A-Z]'))) {
                finalDescription = itemName;
              }
            }
            
            // MERGE MULTI-LINE TEXT: Handle SAP PDFs where fields are split across lines
            // Extract Manufacturer Part No which may be on a separate line
            String? manufacturerPartNo = item['manufacturerPartNo'] ?? 
                                       item['manufacturerPart'] ?? 
                                       item['manufacturer_part_no'] ??
                                       item['vendorPartNo'] ??
                                       item['vendorPartNumber'] ??
                                       item['vendor_part_no'];
            
            // If manufacturerPartNo exists and itemName seems incomplete, consider merging
            String mergedItemName = itemName;
            if (manufacturerPartNo != null && manufacturerPartNo.isNotEmpty) {
              // If itemName is short and manufacturerPartNo looks like a continuation, merge them
              if (itemName.length < 20 && manufacturerPartNo.length > 5) {
                mergedItemName = '$itemName $manufacturerPartNo'.trim();
                debugPrint('✅ Merged multi-line text: itemName + manufacturerPartNo');
              }
              // Also add to description if description is empty
              if (finalDescription.isEmpty) {
                finalDescription = manufacturerPartNo;
              } else if (!finalDescription.contains(manufacturerPartNo)) {
                finalDescription = '$finalDescription $manufacturerPartNo'.trim();
              }
            }
            
            // SAP/ALMARAI FORMAT: Prioritize Item No, then SAP Code, then Vendor Part No, then Manufacturer Part No
            String? finalItemCode = itemCode;
            if (finalItemCode == null || finalItemCode.isEmpty) {
              // Try SAP Code
              finalItemCode = item['sapCode'] ?? 
                            item['SAPCode'] ?? 
                            item['sap_code'] ??
                            item['materialCode'] ??
                            item['material_code'];
            }
            if (finalItemCode == null || finalItemCode.isEmpty) {
              // Try Vendor Part No
              finalItemCode = item['vendorPartNo'] ?? 
                            item['vendorPartNumber'] ?? 
                            item['vendor_part_no'] ??
                            item['partNumber'] ??
                            item['part_number'];
            }
            if (finalItemCode == null || finalItemCode.isEmpty) {
              // Try Manufacturer Part No
              finalItemCode = manufacturerPartNo;
            }
            if (finalItemCode == null || finalItemCode.isEmpty) {
              // Try Item No (convert to string if it's a number)
              dynamic itemNoRaw = item['itemNo'] ?? 
                            item['itemNumber'] ?? 
                            item['item_no'];
              finalItemCode = itemNoRaw is String ? itemNoRaw : (itemNoRaw is num ? itemNoRaw.toString() : null);
            }
            
            // NULL HANDLING: Ensure all required fields have defaults
            // CRITICAL: quantity, unitPrice, and total are already converted to double by _convertToFloat()
            // But add extra safety to ensure they're definitely doubles (not strings) before creating LineItem
            final finalQuantity = quantity > 0 ? quantity.toDouble() : 0.0;
            final finalUnitPrice = unitPrice > 0 ? unitPrice.toDouble() : 0.0;
            final finalUnit = (unit.isNotEmpty && unit != 'null') ? unit : 'pcs';
            final finalTotal = total > 0 ? total.toDouble() : (finalQuantity * finalUnitPrice);
            
            // FILTER OUT PDF JUNK: Check if mergedItemName contains PDF corruption patterns
            final isJunkData = mergedItemName.contains(RegExp(r'[<>{}[\]\\|`~!@#$%^&*()_+\-=\s]{10,}')) || // Too many special chars
                              mergedItemName.contains('endstream') ||
                              mergedItemName.contains('stream') ||
                              mergedItemName.contains('obj') ||
                              mergedItemName.contains('endobj') ||
                              mergedItemName.contains('xref') ||
                              mergedItemName.contains('trailer') ||
                              mergedItemName.contains('FlateDecode') ||
                              (mergedItemName.length > 200 && !RegExp(r'[a-zA-Z]{5,}').hasMatch(mergedItemName)); // Long but no readable text
            
            if (mergedItemName.isNotEmpty && !isJunkData) {
              // Clean mergedItemName - remove any remaining PDF artifacts
              String cleanItemName = mergedItemName
                  .replaceAll(RegExp(r'[<>{}[\]\\|`~!@#$%^&*()_+\-=]{3,}'), ' ') // Remove sequences of special chars
                  .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
                  .trim();
              
              // If after cleaning it's too short or still looks like junk, skip it
              if (cleanItemName.length < 3 || 
                  cleanItemName.length > 500 ||
                  !RegExp(r'[a-zA-Z0-9]').hasMatch(cleanItemName)) {
                debugPrint('⚠️ Skipping junk item after cleaning: ${cleanItemName.length > 50 ? cleanItemName.substring(0, 50) : cleanItemName}...');
                continue; // Skip this item
              }
              
              // ROW ANCHORING: Validate that all fields from the same row are properly grouped
              // Ensure description preserves technical specs and merged multi-line text
              // Use mergedItemName if we merged manufacturerPartNo
              final finalItemName = mergedItemName.isNotEmpty ? mergedItemName : cleanItemName;
              
              // CRITICAL: Remove ALL newlines from description and escape quotes
              String cleanDescription = finalDescription.isNotEmpty ? finalDescription : '';
              if (cleanDescription.isNotEmpty) {
                cleanDescription = cleanDescription
                    .replaceAll('\n', ' ')  // Remove all newlines
                    .replaceAll('\r', ' ')  // Remove carriage returns
                    .replaceAll(RegExp(r'\s+'), ' ')  // Normalize whitespace
                    .replaceAll('"', '\\"')  // Escape quotes to prevent JSON errors
                    .trim();
              }
              
              final anchoredItem = LineItem(
                itemName: finalItemName,
                itemCode: finalItemCode,
                description: cleanDescription.isNotEmpty ? cleanDescription : null,
                quantity: finalQuantity,
                unit: finalUnit,
                unitPrice: finalUnitPrice,
                total: finalTotal, // Already calculated with null handling
              );
              
              // Validate data integrity - ensure numeric fields are properly converted
              if (anchoredItem.quantity > 0 && anchoredItem.unitPrice > 0) {
                lineItems.add(anchoredItem);
                debugPrint('✅ Row-anchored item (SAP format): ItemNo=$itemNo, SAPCode=$sapCode, Name=${anchoredItem.itemName}, Qty=${anchoredItem.quantity}, UOM=${anchoredItem.unit}, Price=${anchoredItem.unitPrice}, Total=${anchoredItem.total}');
              } else {
                debugPrint('⚠️ Skipping invalid item (missing quantity or price): $finalItemName');
              }
              } else if (isJunkData) {
              debugPrint('⚠️ Skipping junk PDF data: ${itemName.substring(0, itemName.length > 50 ? 50 : itemName.length)}...');
            }
          }
        }
      }
      
      // If no line items from JSON, try to extract from original text with multiple patterns
      if (lineItems.isEmpty && originalText.isNotEmpty) {
        debugPrint('⚠️ No line items found in JSON, attempting fallback extraction from text...');
        
        // Pattern 1: Table with Item No, Description, Quantity, Unit Price, Total
        // Matches: "10 | GLOVES | 5.00 | 180.00 | 900.00"
        final tablePattern1 = RegExp(
          r'(\d+)\s*[|]?\s*(.+?)\s*[|]?\s*(\d+(?:\.\d+)?)\s*[|]?\s*(\d+(?:\.\d+)?)\s*[|]?\s*(\d+(?:\.\d+)?)',
          caseSensitive: false,
          dotAll: true,
        );
        
        // Pattern 2: Look for "Item No" followed by description and numbers
        final tablePattern2 = RegExp(
          r'Item\s+No[.:\s]*(\d+)[\s\S]*?Description[:\s]*(.+?)(?:\n|Quantity|Qty|Unit|Price|Total)[\s\S]*?(?:Quantity|Qty)[:\s]*(\d+(?:\.\d+)?)[\s\S]*?(?:Unit\s+Price|Price)[:\s]*(\d+(?:\.\d+)?)[\s\S]*?(?:Total|Total\s+Price)[:\s]*(\d+(?:\.\d+)?)',
          caseSensitive: false,
          dotAll: true,
        );
        
        // Pattern 3: Simple table rows with description and prices
        // Matches rows like: "GLOVES HYFLEXULTRA-LITE PU GLV8 -ANSELL | 5.00 | 180.00 | 900.00"
        final tablePattern3 = RegExp(
          r'([A-Z][A-Z\s\-]+(?:GLV|GLV8|ANSELL|GLOVES)[A-Z\s\-]*)\s+(\d+(?:\.\d+)?)\s+(?:BAG|PCS|EA|KG|UNIT)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)',
          caseSensitive: false,
        );
        
        // Pattern 4: SAP Code pattern - "1290441 | Description | 5.00 | 180.00 | 900.00"
        final tablePattern4 = RegExp(
          r'(\d{6,})\s*[|]?\s*(.+?)\s*[|]?\s*(\d+(?:\.\d+)?)\s*[|]?\s*(\d+(?:\.\d+)?)\s*[|]?\s*(\d+(?:\.\d+)?)',
          caseSensitive: false,
          dotAll: true,
        );
        
        // Try all patterns
        final allPatterns = [tablePattern1, tablePattern2, tablePattern3, tablePattern4];
        
        for (int i = 0; i < allPatterns.length; i++) {
          final pattern = allPatterns[i];
          final matches = pattern.allMatches(originalText);
          
          for (final match in matches) {
            try {
              String? itemName;
              String? itemCode;
              double qty = 0.0;
              double unitPrice = 0.0;
              double total = 0.0;
              String unit = 'pcs';
              
              if (i == 0 || i == 3) {
                // Pattern 1 or 4: itemNo/itemCode, description, qty, price, total
                itemCode = match.group(1);
                itemName = match.group(2)?.trim();
                qty = double.tryParse(match.group(3) ?? '0') ?? 0.0;
                unitPrice = double.tryParse(match.group(4) ?? '0') ?? 0.0;
                total = double.tryParse(match.group(5) ?? '0') ?? 0.0;
              } else if (i == 1) {
                // Pattern 2: structured with labels
                itemCode = match.group(1);
                itemName = match.group(2)?.trim();
                qty = double.tryParse(match.group(3) ?? '0') ?? 0.0;
                unitPrice = double.tryParse(match.group(4) ?? '0') ?? 0.0;
                total = double.tryParse(match.group(5) ?? '0') ?? 0.0;
              } else if (i == 2) {
                // Pattern 3: description, qty, unit, price, total
                itemName = match.group(1)?.trim();
                qty = double.tryParse(match.group(2) ?? '0') ?? 0.0;
                unitPrice = double.tryParse(match.group(3) ?? '0') ?? 0.0;
                total = double.tryParse(match.group(4) ?? '0') ?? 0.0;
                // Try to extract unit from context
                final unitMatch = RegExp(r'(\d+(?:\.\d+)?)\s+(BAG|PCS|EA|KG|UNIT|PIECE)', caseSensitive: false).firstMatch(originalText.substring(match.start, match.end + 50));
                if (unitMatch != null) {
                  unit = unitMatch.group(2)?.toLowerCase() ?? 'pcs';
                }
              }
              
              if (itemName != null && itemName.isNotEmpty && itemName.length > 3 && qty > 0 && unitPrice > 0) {
                if (total == 0.0) {
                  total = qty * unitPrice;
                }
                
                lineItems.add(LineItem(
                  itemName: itemName,
                  itemCode: itemCode,
                  description: null,
                  quantity: qty,
                  unit: unit,
                  unitPrice: unitPrice,
                  total: total,
                ));
                debugPrint('✅ Extracted line item from text: $itemName, Qty: $qty, Price: $unitPrice');
              }
            } catch (e) {
              debugPrint('Error extracting line item from match: $e');
            }
          }
          
          if (lineItems.isNotEmpty) {
            debugPrint('✅ Successfully extracted ${lineItems.length} line items using pattern ${i + 1}');
            break;
          }
        }
        
        // If still no items, try a more aggressive pattern matching common PO table structures
        if (lineItems.isEmpty) {
          // Look for any sequence that looks like: number, text, number, number, number
          final aggressivePattern = RegExp(
            r'(\d+)\s+([A-Z][A-Z\s\-\d]+(?:GLV|GLOVES|ANSELL|HYFLEX)[A-Z\s\-\d]*)\s+(\d+(?:\.\d+)?)\s+(?:BAG|PCS|EA)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)',
            caseSensitive: false,
          );
          
          final aggressiveMatches = aggressivePattern.allMatches(originalText);
          for (final match in aggressiveMatches) {
            try {
              final itemCode = match.group(1);
              final itemName = match.group(2)?.trim();
              final qty = double.tryParse(match.group(3) ?? '0') ?? 0.0;
              final unitPrice = double.tryParse(match.group(4) ?? '0') ?? 0.0;
              final total = double.tryParse(match.group(5) ?? '0') ?? 0.0;
              
              if (itemName != null && itemName.isNotEmpty && qty > 0 && unitPrice > 0) {
                lineItems.add(LineItem(
                  itemName: itemName,
                  itemCode: itemCode,
                  description: null,
                  quantity: qty,
                  unit: 'pcs',
                  unitPrice: unitPrice,
                  total: total > 0 ? total : (qty * unitPrice),
                ));
                debugPrint('✅ Extracted line item (aggressive): $itemName');
              }
            } catch (e) {
              debugPrint('Error in aggressive extraction: $e');
            }
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
      String? quotationReference = jsonData['quotationReference']?.toString().trim();
      final vendorName = jsonData['vendorName']?.toString().trim();
      String? customerNameFromJson = jsonData['customerName']?.toString().trim();
      String? customerAddress = jsonData['customerAddress']?.toString().trim();
      String? customerEmail = jsonData['customerEmail']?.toString().trim();
      
      // If quotation reference not found in JSON, try to extract from original text
      if ((quotationReference == null || quotationReference.isEmpty || quotationReference == 'null') && originalText.isNotEmpty) {
        final quotationPatterns = [
          RegExp(r'Quotation\s*(?:Reference|No|Number|#)[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'Quote\s*(?:No|Number|#)[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'QTN[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
          RegExp(r'Quotation\s*Reference\s*N[°o][:\s]+([A-Z0-9\-]+)', caseSensitive: false),
        ];
        
        for (final pattern in quotationPatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            quotationReference = match.group(1)!.trim();
            debugPrint('✅ Extracted quotation reference from text: $quotationReference');
            break;
          }
        }
      }
      
      // If customer address not found, try to extract from original text
      if ((customerAddress == null || customerAddress.isEmpty || customerAddress == 'null') && originalText.isNotEmpty) {
        final addressPatterns = [
          RegExp(r'Please\s+deliver\s+to[:\s]+(.+?)(?:\n\n|\n[A-Z]|$)', caseSensitive: false, dotAll: true),
          RegExp(r'Ship\s+To[:\s]+(.+?)(?:\n\n|\n[A-Z]|$)', caseSensitive: false, dotAll: true),
          RegExp(r'Delivery\s+Address[:\s]+(.+?)(?:\n\n|\n[A-Z]|$)', caseSensitive: false, dotAll: true),
        ];
        
        for (final pattern in addressPatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            customerAddress = match.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
            debugPrint('✅ Extracted customer address from text');
            break;
          }
        }
      }
      
      // If customer email not found, try to extract from original text
      if ((customerEmail == null || customerEmail.isEmpty || customerEmail == 'null') && originalText.isNotEmpty) {
        final emailPattern = RegExp(r'Email\s*(?:ID|Address)?[:\s]+([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', caseSensitive: false);
        final emailMatch = emailPattern.firstMatch(originalText);
        if (emailMatch != null && emailMatch.group(1) != null) {
          customerEmail = emailMatch.group(1)!.trim();
          debugPrint('✅ Extracted customer email from text: $customerEmail');
        }
      }
      
      // Extract customer name - PRIORITIZE customerName from JSON, NOT vendorName
      String finalCustomerName = '';
      
      // First, try customerName from JSON (this is the correct field)
      if (customerNameFromJson != null && 
          customerNameFromJson.isNotEmpty && 
          customerNameFromJson != 'N/A' && 
          customerNameFromJson != 'null' &&
          customerNameFromJson.toLowerCase() != 'unknown') {
        finalCustomerName = customerNameFromJson;
        debugPrint('✅ Using customerName from JSON: $finalCustomerName');
      }
      
      // If not found, try to extract from customerAddress (e.g., "Almarai Company Plant")
      // This is better than using vendorName because the address usually contains the customer name
      if ((finalCustomerName.isEmpty || finalCustomerName == 'Unknown') && customerAddress != null && customerAddress.isNotEmpty) {
        // Look for company name patterns in address
        // Pattern: "Company Name" or "Company Name Plant" or "Company Name, Address"
        final companyPatterns = [
          RegExp(r'^([A-Z][A-Za-z\s&]+(?:Company|Corp|Corporation|Ltd|Limited|Inc|Incorporated|LLC|Group|Industries|Services|Trading|International|Global))', caseSensitive: false),
          RegExp(r'^([A-Z][A-Za-z\s&]+)\s+(?:Plant|Office|Headquarters|HQ|Branch)', caseSensitive: false),
          RegExp(r'^([A-Z][A-Za-z\s&]+),', caseSensitive: false),
        ];
        
        for (final pattern in companyPatterns) {
          final match = pattern.firstMatch(customerAddress);
          if (match != null && match.group(1) != null) {
            final extracted = match.group(1)!.trim();
            if (extracted.length > 3 && extracted.length < 100) {
              finalCustomerName = extracted;
              debugPrint('✅ Extracted customer name from address: $finalCustomerName');
              break;
            }
          }
        }
      }
      
      // If still not found, try to extract from original text
      if ((finalCustomerName.isEmpty || finalCustomerName == 'Unknown') && originalText.isNotEmpty) {
        // Look for common customer name patterns
        final namePatterns = [
          RegExp(r'Customer\s*Name[:\s]+([A-Z][A-Za-z\s&]+(?:Company|Corp|Corporation|Ltd|Limited|Inc)?)', caseSensitive: false),
          RegExp(r'Bill\s+To[:\s]+([A-Z][A-Za-z\s&]+)', caseSensitive: false),
          RegExp(r'Ship\s+To[:\s]+([A-Z][A-Za-z\s&]+)', caseSensitive: false),
          RegExp(r'Buyer[:\s]+([A-Z][A-Za-z\s&]+)', caseSensitive: false),
          RegExp(r'Vendor[:\s]+([A-Z][A-Za-z\s&]+)', caseSensitive: false),
          // Look for company names in the text (common patterns)
          RegExp(r'\b([A-Z][A-Za-z\s&]+(?:Company|Corp|Corporation|Ltd|Limited|Inc|Incorporated))\b', caseSensitive: false),
        ];
        
        for (final pattern in namePatterns) {
          final match = pattern.firstMatch(originalText);
          if (match != null && match.group(1) != null) {
            final extracted = match.group(1)!.trim();
            // Filter out common false positives
            if (extracted.length > 3 && 
                extracted.length < 100 &&
                !extracted.toLowerCase().contains('purchase') &&
                !extracted.toLowerCase().contains('order') &&
                !extracted.toLowerCase().contains('delivery') &&
                !extracted.toLowerCase().contains('shipping')) {
              finalCustomerName = extracted;
              debugPrint('✅ Extracted customer name from text: $finalCustomerName');
              break;
            }
          }
        }
      }
      
      // Final fallback - Only use vendorName as absolute last resort if nothing else works
      // But prefer to keep it as Unknown rather than showing vendor name as customer name
      if (finalCustomerName.isEmpty || finalCustomerName == 'Unknown') {
        // Only use vendorName if it's clearly a customer name pattern (contains "Company", "LLC", etc.)
        // Otherwise, keep as Unknown to avoid confusion
        if (vendorName != null && 
            vendorName.isNotEmpty && 
            vendorName != 'N/A' && 
            vendorName.toLowerCase() != 'unknown' &&
            (vendorName.contains('Company') || 
             vendorName.contains('LLC') || 
             vendorName.contains('Ltd') ||
             vendorName.contains('Corp'))) {
          finalCustomerName = vendorName;
          debugPrint('⚠️ Using vendorName as last resort for customerName: $finalCustomerName');
        } else {
          finalCustomerName = 'Unknown';
          debugPrint('⚠️ Could not determine customer name, keeping as Unknown');
        }
      }
      
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
        currency: extractedCurrency.isNotEmpty ? extractedCurrency : 'AED',
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
      
      // Handle formats like "28Jan26" or "02Feb26" (DDMonYY)
      final compactPattern = RegExp(r'(\d{1,2})([a-z]{3})(\d{2,4})', caseSensitive: false);
      final compactMatch = compactPattern.firstMatch(cleanDate);
      if (compactMatch != null) {
        final day = int.parse(compactMatch.group(1)!);
        final monthName = compactMatch.group(2)!.toLowerCase();
        final yearStr = compactMatch.group(3)!;
        int year = int.parse(yearStr);
        
        // If 2-digit year, assume 2000s if > 50, else 2000s
        if (yearStr.length == 2) {
          year = year > 50 ? 1900 + year : 2000 + year;
        }
        
        final monthNames = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        };
        
        final month = monthNames[monthName];
        if (month != null) {
          return DateTime(year, month, day);
        }
      }
      
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
   - Extract "Purchase Requisition" number as inquiryNumber (use the first Purchase Requisition number found)
   - Extract "Plant" as customerName (if customer name not found elsewhere)
   - For EACH row in the table (excluding header row), extract:
     * "Short Text" or "Material Description" → itemName (REQUIRED - must extract for every row)
     * "Material" or "Material Code" → itemCode
     * "Quantity Requested" or "Quantity" → quantity (convert to number, default to 1.0 if missing)
     * "Unit of Measure" or "Unit" or "UOM" → unit (default to "EA" or "PC" if not found)
     * "VPN" or "Part Number" → manufacturerPart
     * "Class" → classCode
     * "Plant" → plant
   - CRITICAL: Extract ALL rows from the table, even if some fields are missing or zero
   - If "Short Text" is empty but "Material" has a value, use "Material" as itemName
   - DO NOT skip any rows - extract every item in the table

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
- Extract EVERY row from the table - do not skip any items
- If "Short Text" is empty, use "Material" code or description as itemName
- If quantity is missing, use 1.0 as default
- If unit is missing, use "EA" or "PC" as default based on context
- If a field is not found, use null for optional fields or reasonable defaults
- The PDF is provided as binary data - process it as a visual document, not as extracted text
- IMPORTANT: The "items" array must contain ALL items from the table, even if some fields are missing
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
          'maxOutputTokens': 8192, // Increased for complex documents with many line items
          'temperature': 0.1, // Lower temperature for more consistent extraction
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
        // Ensure itemName is never empty - use itemCode or a default if missing
        String itemName = item['itemName'] as String? ?? '';
        if (itemName.isEmpty) {
          itemName = item['itemCode'] as String? ?? 
                     item['description'] as String? ?? 
                     'Unknown Item';
        }
        
        return InquiryItem(
          itemName: itemName,
          itemCode: item['itemCode'] as String?,
          description: item['description'] as String? ?? itemName,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: item['unit'] as String? ?? 'EA',
          manufacturerPart: item['manufacturerPart'] as String?,
          classCode: item['classCode'] as String?,
          plant: item['plant'] as String?,
        );
      }).toList();
      
      // Log warning if no items were extracted
      if (items.isEmpty) {
        debugPrint('⚠️ WARNING: No items extracted from PDF. JSON data: $jsonData');
      } else {
        debugPrint('✅ Successfully extracted ${items.length} items from PDF');
      }

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
        final result = await _j.generateContent([Content.text(prompt)])
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
        final result = await _j.generateContent([Content.text(prompt)])
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

