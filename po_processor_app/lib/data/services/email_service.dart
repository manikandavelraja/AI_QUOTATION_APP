import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import '../../core/constants/app_constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for handling email operations (fetching and sending)
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  final _storage = const FlutterSecureStorage();
  static const String _emailPasswordKey = 'email_app_password';
  static const String _gmailAccessTokenKey = 'gmail_access_token';
  static const String _gmailRefreshTokenKey = 'gmail_refresh_token';
  
  GoogleSignIn? _googleSignIn;
  gmail.GmailApi? _gmailApi;

  /// Get stored email app password (for SMTP)
  Future<String?> getEmailPassword() async {
    try {
      return await _storage.read(key: _emailPasswordKey);
    } catch (e) {
      debugPrint('Error reading email password: $e');
      return null;
    }
  }

  /// Store email app password securely
  Future<void> setEmailPassword(String password) async {
    try {
      await _storage.write(key: _emailPasswordKey, value: password);
    } catch (e) {
      debugPrint('Error storing email password: $e');
    }
  }

  /// Initialize Gmail API with OAuth2 - automatically uses stored tokens
  /// Only prompts for sign-in if tokens are missing or expired
  Future<void> _initializeGmailApi({bool silent = true}) async {
    try {
      if (_gmailApi != null) return;
      
      // Check if we have a stored access token
      final storedToken = await _storage.read(key: _gmailAccessTokenKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        // Try to use stored token
        try {
          final headers = {
            'Authorization': 'Bearer $storedToken',
            'Content-Type': 'application/json',
          };
          final authClient = _AuthenticatedHttpClient(http.Client(), headers);
          _gmailApi = gmail.GmailApi(authClient);
          
          // Test if token is still valid by making a simple API call
          await _gmailApi!.users.getProfile('me');
          debugPrint('✅ Gmail API initialized automatically with stored token');
          return;
        } catch (e) {
          // Token expired or invalid, try to refresh
          debugPrint('⚠️ Stored token invalid, attempting refresh...');
          final refreshed = await _refreshAccessToken();
          if (refreshed) {
            debugPrint('✅ Token refreshed successfully');
            return;
          }
          // If refresh failed, clear tokens and re-authenticate
          await _storage.delete(key: _gmailAccessTokenKey);
          await _storage.delete(key: _gmailRefreshTokenKey);
        }
      }
      
      // No stored token or refresh failed - need to sign in
      if (silent) {
        // For automatic access, try silent sign-in first
        _googleSignIn = GoogleSignIn(
          scopes: [
            'https://www.googleapis.com/auth/gmail.readonly',
            'https://www.googleapis.com/auth/gmail.modify',
          ],
          // Configure client ID for web if available
          clientId: kIsWeb && AppConstants.gmailWebClientId != null 
              ? AppConstants.gmailWebClientId 
              : null,
        );
        
        // Try silent sign-in (uses cached account if available) with timeout
        try {
          final account = await _googleSignIn!.signInSilently()
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  debugPrint('⚠️ Silent sign-in timed out');
                  return null;
                },
              );
          if (account != null) {
            final auth = await account.authentication
                .timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    throw Exception('Authentication timeout');
                  },
                );
            if (auth.accessToken != null) {
              await _storeTokens(auth.accessToken!, auth.idToken);
              await _createGmailApiClient(auth.accessToken!);
              debugPrint('✅ Gmail API initialized automatically via silent sign-in');
              return;
            }
          }
        } catch (e) {
          debugPrint('⚠️ Silent sign-in failed: $e');
          // Continue to interactive sign-in
        }
      }
      
      // If silent sign-in failed, prompt user (only if not silent mode)
      String? accessToken;
      String? idToken;
      
      try {
        // Initialize Google Sign-In with proper web configuration
        _googleSignIn ??= GoogleSignIn(
          scopes: [
            'https://www.googleapis.com/auth/gmail.readonly',
            'https://www.googleapis.com/auth/gmail.modify',
          ],
          // Configure client ID for web if available
          clientId: kIsWeb && AppConstants.gmailWebClientId != null 
              ? AppConstants.gmailWebClientId 
              : null,
        );
        
        debugPrint('🔐 Starting Gmail sign-in for kumarionix07@gmail.com...');
        debugPrint('🔐 Opening Google Sign-In window...');
        
        // This should open the sign-in window with timeout for mobile
        final account = await _googleSignIn!.signIn()
            .timeout(
              const Duration(seconds: 120), // 2 minutes for mobile OAuth
              onTimeout: () {
                throw Exception('Sign-in timed out. Please try again and ensure popups are not blocked.');
              },
            );
        
        if (account == null) {
          debugPrint('⚠️ Sign-in was cancelled by user');
          throw Exception('Gmail sign-in was cancelled. Please try again and complete the sign-in process.');
        }
        
        debugPrint('✅ Signed in as: ${account.email}');
        
        // Request scopes for Gmail access
        debugPrint('🔐 Requesting Gmail access permissions...');
        final hasScopes = await _googleSignIn!.requestScopes([
          'https://www.googleapis.com/auth/gmail.readonly',
          'https://www.googleapis.com/auth/gmail.modify',
        ]);
        
        if (!hasScopes) {
          throw Exception('Gmail authorization failed - please grant Gmail access permissions when prompted.');
        }
        
        debugPrint('✅ Gmail permissions granted');
        
        // Get access token
        final auth = await account.authentication;
        accessToken = auth.accessToken;
        idToken = auth.idToken;
        
        if (accessToken == null || accessToken.isEmpty) {
          throw Exception('Failed to get access token after sign-in. Please try again.');
        }
        
        debugPrint('✅ Access token obtained successfully');
      } catch (e) {
        debugPrint('❌ Google Sign-In error: $e');
        final errorStr = e.toString();
        
        // If google_sign_in fails (especially on web), provide helpful message
        if (errorStr.contains('MissingPluginException') || 
            errorStr.contains('No implementation found') ||
            errorStr.contains('plugins.flutter.io/google_sign_in')) {
          // On web, if Google Sign-In plugin fails, it means OAuth2 client ID is not configured
          if (kIsWeb) {
            debugPrint('⚠️ Google Sign-In plugin not available on web - OAuth2 client ID required');
            // Clear any partial state
            _gmailApi = null;
            throw Exception(
              'Gmail access on web requires OAuth2 client ID configuration.\n\n'
              'For now, please use manual upload:\n'
              '1. Download PDFs from your Gmail inbox\n'
              '2. Use "Upload Customer Inquiry" or "Upload PO" buttons\n\n'
              'To enable automatic email access, configure OAuth2 in Google Cloud Console.'
            );
          }
        }
        
        // For sign-in cancellation, provide specific message
        if (errorStr.contains('cancelled')) {
          _gmailApi = null;
          throw Exception('Sign-in was cancelled. Please try again and complete the sign-in process.');
        }
        
        // Clear state on any other error and rethrow with original message
        _gmailApi = null;
        rethrow;
      }
      
      // Store tokens for future automatic access
      await _storeTokens(accessToken, idToken);
      await _createGmailApiClient(accessToken);
      debugPrint('✅ Gmail API initialized');
    } catch (e) {
      debugPrint('❌ Error initializing Gmail API: $e');
      rethrow;
    }
  }
  
  /// Store access and refresh tokens securely
  Future<void> _storeTokens(String accessToken, String? idToken) async {
    await _storage.write(key: _gmailAccessTokenKey, value: accessToken);
    if (idToken != null) {
      await _storage.write(key: _gmailRefreshTokenKey, value: idToken);
    }
  }
  
  /// Create Gmail API client with access token
  Future<void> _createGmailApiClient(String accessToken) async {
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
    final authClient = _AuthenticatedHttpClient(http.Client(), headers);
    _gmailApi = gmail.GmailApi(authClient);
  }
  
  /// Refresh access token using refresh token (if available)
  Future<bool> _refreshAccessToken() async {
    try {
      final refreshToken = await _storage.read(key: _gmailRefreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }
      
      // Note: Google Sign-In handles token refresh automatically
      // This is a placeholder for future implementation
      // For now, we'll rely on Google Sign-In's automatic token refresh
      return false;
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      return false;
    }
  }

  /// Fetch emails from inbox with attachments (PDF/DOC)
  /// Automatically uses stored credentials for authentication
  /// Returns list of email messages with attachments
  Future<List<EmailMessage>> fetchInquiryEmails({
    int maxResults = 10,
    String? query,
  }) async {
    try {
      debugPrint('📧 Fetching inquiry emails automatically...');
      
      // Ensure Gmail API is initialized before fetching
      if (_gmailApi == null) {
        try {
          // Try silent initialization first (uses stored tokens)
          await _initializeGmailApi(silent: true);
        } catch (initError) {
          debugPrint('❌ Gmail API silent initialization error: $initError');
          final errorStr = initError.toString();
          
          // If it's a sign-in related error, try with user interaction
          if (errorStr.contains('sign in') || 
              errorStr.contains('cancelled') ||
              errorStr.contains('authentication') ||
              errorStr.contains('token') ||
              errorStr.contains('MissingPluginException')) {
            debugPrint('🔄 Retrying with user interaction...');
            try {
              await _initializeGmailApi(silent: false);
            } catch (interactiveError) {
              debugPrint('❌ Interactive initialization also failed: $interactiveError');
              // Re-throw with a user-friendly message
              throw Exception('Please sign in with your Gmail account. A sign-in window will open when you tap "GetFromMail".');
            }
          } else {
            // For other errors, rethrow
            rethrow;
          }
        }
      }
      
      if (_gmailApi == null) {
        throw Exception('Failed to initialize Gmail API. Please sign in with Gmail to access your emails.');
      }
      
      return await _fetchInquiryEmailsViaGmailAPI(maxResults: maxResults, query: query);
    } catch (e) {
      debugPrint('❌ Error fetching inquiry emails: $e');
      // Provide more helpful error message
      final errorStr = e.toString();
      if (errorStr.contains('Gmail API not initialized') || 
          errorStr.contains('Failed to initialize')) {
        throw Exception('Please sign in with your Gmail account to access emails. Tap "GetFromMail" again and sign in when prompted.');
      }
      rethrow;
    }
  }
  
  /// Internal method to fetch inquiry emails via Gmail API
  Future<List<EmailMessage>> _fetchInquiryEmailsViaGmailAPI({
    int maxResults = 10,
    String? query,
  }) async {
    try {
      debugPrint('📧 Fetching inquiry emails via Gmail API...');
      
      // Double-check that Gmail API is initialized
      if (_gmailApi == null) {
        debugPrint('⚠️ Gmail API is null, attempting to initialize...');
        await _initializeGmailApi(silent: false);
        if (_gmailApi == null) {
          throw Exception('Gmail API not initialized. Please sign in with Gmail.');
        }
      }
      
      // Search for inquiry-related emails - filter by subject containing "Inquiry" (case-insensitive)
      // Gmail search is case-insensitive by default, but we'll be explicit
      final searchQuery = query ?? 'subject:inquiry has:attachment (filename:pdf OR filename:doc OR filename:docx)';
      
      final listResponse = await _gmailApi!.users.messages.list(
        'me',
        q: searchQuery,
        maxResults: maxResults,
      );
      
      if (listResponse.messages == null || listResponse.messages!.isEmpty) {
        debugPrint('No inquiry emails found');
        return [];
      }
      
      final emails = <EmailMessage>[];
      
      for (final message in listResponse.messages!) {
        try {
          // Get full message
          final fullMessage = await _gmailApi!.users.messages.get(
            'me',
            message.id!,
            format: 'full',
          );
          
          // Parse message
          final email = _parseGmailMessage(fullMessage);
          
          // Filter for inquiry-related emails with PDF/DOC attachments
          // Also check if subject contains "Inquiry" (case-insensitive)
          final subjectLower = email.subject.toLowerCase();
          if (email.attachments.isNotEmpty && 
              (subjectLower.contains('inquiry') || 
               subjectLower.contains('rfq') || 
               subjectLower.contains('quotation') ||
               subjectLower.contains('request'))) {
            emails.add(email);
          }
        } catch (e) {
          debugPrint('Error processing email ${message.id}: $e');
          continue;
        }
      }
      
      debugPrint('✅ Fetched ${emails.length} inquiry emails');
      return emails;
    } catch (e) {
      debugPrint('❌ Error fetching inquiry emails: $e');
      // If it's an auth error, clear the API and ask user to sign in again
      if (e.toString().contains('401') || e.toString().contains('unauthorized')) {
        _gmailApi = null;
        await _googleSignIn?.signOut();
        throw Exception('Gmail authentication expired. Please sign in again.');
      }
      rethrow;
    }
  }

  /// Fetch inquiry emails from kumarionix07@gmail.com
  /// Searches for unread emails with PDF attachments
  Future<List<EmailMessage>> fetchInquiryFromGmail({
    int maxResults = 10,
  }) async {
    try {
      debugPrint('📧 Fetching inquiry emails from kumarionix07@gmail.com...');
      
      // Ensure Gmail API is initialized before fetching
      if (_gmailApi == null) {
        try {
          // Try silent initialization first (uses stored tokens)
          await _initializeGmailApi(silent: true);
        } catch (initError) {
          debugPrint('❌ Gmail API silent initialization error: $initError');
          final errorStr = initError.toString();
          
          // If it's a sign-in related error, try with user interaction
          if (errorStr.contains('sign in') || 
              errorStr.contains('cancelled') ||
              errorStr.contains('authentication') ||
              errorStr.contains('token') ||
              errorStr.contains('MissingPluginException')) {
            debugPrint('🔄 Retrying with user interaction...');
            try {
              await _initializeGmailApi(silent: false);
            } catch (interactiveError) {
              debugPrint('❌ Interactive initialization also failed: $interactiveError');
              throw Exception('Please sign in with your Gmail account. A sign-in window will open when you tap "GetFromMail".');
            }
          } else {
            rethrow;
          }
        }
      }
      
      if (_gmailApi == null) {
        throw Exception('Failed to initialize Gmail API. Please sign in with Gmail to access your emails.');
      }
      
      // Search for unread emails in inbox with PDF attachments (inquiries sent TO you)
      // Don't filter by from/to - just get all unread emails with PDFs in your inbox
      // The 'from' field in the email will tell us who sent it (the sender email we want to use)
      final searchQuery = 'is:unread in:inbox has:attachment filename:pdf';
      
      debugPrint('🔍 Searching for inquiry emails in inbox with query: $searchQuery');
      
      final listResponse = await _gmailApi!.users.messages.list(
        'me',
        q: searchQuery,
        maxResults: maxResults,
      );
      
      if (listResponse.messages == null || listResponse.messages!.isEmpty) {
        debugPrint('No unread inquiry emails found from kumarionix07@gmail.com');
        return [];
      }
      
      debugPrint('📬 Found ${listResponse.messages!.length} unread emails, processing...');
      
      final emails = <EmailMessage>[];
      
      for (final message in listResponse.messages!) {
        try {
          // Get full message with attachments
          final fullMessage = await _gmailApi!.users.messages.get(
            'me',
            message.id!,
            format: 'full',
          );
          
          // Parse message
          final email = _parseGmailMessage(fullMessage);
          
          // Fetch attachment data for PDF attachments
          final pdfAttachments = <EmailAttachment>[];
          for (final attachment in email.attachments) {
            if (attachment.name.toLowerCase().endsWith('.pdf')) {
              try {
                if (attachment.attachmentId != null && attachment.messageId != null) {
                  // Fetch the actual attachment data
                  final attachmentData = await fetchAttachmentData(
                    attachment.messageId!,
                    attachment.attachmentId!,
                  );
                  
                  pdfAttachments.add(EmailAttachment(
                    name: attachment.name,
                    data: attachmentData,
                    contentType: attachment.contentType,
                    attachmentId: attachment.attachmentId,
                    messageId: attachment.messageId,
                  ));
                  debugPrint('✅ Extracted PDF attachment: ${attachment.name} (${attachmentData.length} bytes)');
                } else {
                  // If attachment data is already in the attachment object
                  pdfAttachments.add(attachment);
                }
              } catch (e) {
                debugPrint('⚠️ Error fetching attachment ${attachment.name}: $e');
                continue;
              }
            }
          }
          
          // Only add email if it has PDF attachments
          if (pdfAttachments.isNotEmpty) {
            emails.add(EmailMessage(
              id: email.id,
              from: email.from,
              to: email.to,
              replyTo: email.replyTo,
              subject: email.subject,
              body: email.body,
              date: email.date,
              attachments: pdfAttachments,
            ));
            debugPrint('✅ Processed inquiry email: ${email.subject} (${pdfAttachments.length} PDF attachments)');
          }
        } catch (e) {
          debugPrint('⚠️ Error processing email ${message.id}: $e');
          continue;
        }
      }
      
      debugPrint('✅ Successfully fetched ${emails.length} inquiry emails with PDF attachments');
      return emails;
    } catch (e) {
      debugPrint('❌ Error fetching inquiry emails from Gmail: $e');
      // If it's an auth error, clear the API and ask user to sign in again
      if (e.toString().contains('401') || e.toString().contains('unauthorized')) {
        _gmailApi = null;
        await _googleSignIn?.signOut();
        throw Exception('Gmail authentication expired. Please sign in again.');
      }
      rethrow;
    }
  }

  /// Fetch Purchase Order emails from inbox
  /// Uses Gmail API with automatic authentication
  Future<List<EmailMessage>> fetchPOEmails({
    int maxResults = 10,
  }) async {
    try {
      debugPrint('📧 Fetching PO emails automatically...');
      
      // Ensure Gmail API is initialized before fetching
      if (_gmailApi == null) {
        try {
          // Try silent initialization first (uses stored tokens)
          await _initializeGmailApi(silent: true);
        } catch (initError) {
          debugPrint('❌ Gmail API silent initialization error: $initError');
          final errorStr = initError.toString();
          
          // If it's a sign-in related error, try with user interaction
          if (errorStr.contains('sign in') || 
              errorStr.contains('cancelled') ||
              errorStr.contains('authentication') ||
              errorStr.contains('token') ||
              errorStr.contains('MissingPluginException')) {
            debugPrint('🔄 Retrying with user interaction...');
            try {
              await _initializeGmailApi(silent: false);
            } catch (interactiveError) {
              debugPrint('❌ Interactive initialization also failed: $interactiveError');
              throw Exception('Please sign in with your Gmail account. A sign-in window will open when you tap "GetFromMail".');
            }
          } else {
            rethrow;
          }
        }
      }
      
      if (_gmailApi == null) {
        throw Exception('Failed to initialize Gmail API. Please sign in with Gmail to access your emails.');
      }
      
      return await _fetchPOEmailsViaGmailAPI(maxResults: maxResults);
    } catch (e) {
      debugPrint('❌ Error fetching PO emails: $e');
      rethrow;
    }
  }
  
  /// Internal method to fetch PO emails via Gmail API
  Future<List<EmailMessage>> _fetchPOEmailsViaGmailAPI({
    int maxResults = 10,
  }) async {
    try {
      debugPrint('📧 Fetching PO emails via Gmail API...');
      
      // Double-check that Gmail API is initialized
      if (_gmailApi == null) {
        debugPrint('⚠️ Gmail API is null, attempting to initialize...');
        await _initializeGmailApi(silent: false);
        if (_gmailApi == null) {
          throw Exception('Gmail API not initialized. Please sign in with Gmail.');
        }
      }
      
      // Search for PO-related emails - filter by subject containing 'PO' or 'Purchase Order' (case-insensitive)
      final searchQuery = 'subject:(po OR "purchase order") has:attachment filename:pdf';
      
      final listResponse = await _gmailApi!.users.messages.list(
        'me',
        q: searchQuery,
        maxResults: maxResults,
      );
      
      if (listResponse.messages == null || listResponse.messages!.isEmpty) {
        debugPrint('No PO emails found');
        return [];
      }
      
      final emails = <EmailMessage>[];
      
      for (final message in listResponse.messages!) {
        try {
          // Get full message
          final fullMessage = await _gmailApi!.users.messages.get(
            'me',
            message.id!,
            format: 'full',
          );
          
          // Parse message
          final email = _parseGmailMessage(fullMessage);
          
          // Filter for PO-related emails with PDF attachments
          // Also check if subject contains "PO" or "Purchase Order" (case-insensitive)
          final subjectLower = email.subject.toLowerCase();
          if (email.attachments.isNotEmpty && 
              email.attachments.any((att) => att.name.toLowerCase().endsWith('.pdf')) &&
              (subjectLower.contains('po') || subjectLower.contains('purchase order'))) {
            emails.add(email);
          }
        } catch (e) {
          debugPrint('Error processing email ${message.id}: $e');
          continue;
        }
      }
      
      debugPrint('✅ Fetched ${emails.length} PO emails');
      return emails;
    } catch (e) {
      debugPrint('❌ Error fetching PO emails: $e');
      // If it's an auth error, clear the API and try to re-authenticate
      if (e.toString().contains('401') || e.toString().contains('unauthorized')) {
        _gmailApi = null;
        await _storage.delete(key: _gmailAccessTokenKey);
        await _storage.delete(key: _gmailRefreshTokenKey);
        // Try to re-authenticate automatically
        await _initializeGmailApi(silent: true);
        if (_gmailApi != null) {
          // Retry the fetch
          return await _fetchPOEmailsViaGmailAPI(maxResults: maxResults);
        }
        throw Exception('Gmail authentication expired. Please sign in again.');
      }
      rethrow;
    }
  }

  /// Parse Gmail API message to EmailMessage
  EmailMessage _parseGmailMessage(gmail.Message message) {
    try {
      String from = '';
      String? to;
      String? replyTo;
      String subject = '';
      String body = '';
      DateTime date = DateTime.now();
      final attachments = <EmailAttachment>[];
      
      // Extract headers
      debugPrint('📧 Parsing Gmail message headers...');
      for (final header in message.payload?.headers ?? []) {
        final headerName = header.name?.toLowerCase() ?? '';
        final headerValue = header.value ?? '';
        
        // Debug: Log all headers to see what we're getting
        if (headerName == 'from' || headerName == 'to' || headerName == 'reply-to') {
          debugPrint('📧 Header: ${header.name} = $headerValue');
        }
        
        if (headerName == 'from') {
          from = headerValue;
          debugPrint('📧 Raw From header value: $headerValue');
          
          // Extract email address - handle formats like:
          // "Name <email@domain.com>"
          // "email@domain.com"
          // "Name email@domain.com"
          // Try to find email in angle brackets first
          final angleBracketMatch = RegExp(r'<([\w\.-]+@[\w\.-]+\.\w+)>').firstMatch(from);
          if (angleBracketMatch != null) {
            from = angleBracketMatch.group(1)!;
            debugPrint('📧 Extracted From email from angle brackets: $from');
          } else {
            // Try to find email without angle brackets
            final emailMatch = RegExp(r'[\w\.-]+@[\w\.-]+\.\w+').firstMatch(from);
            if (emailMatch != null) {
              from = emailMatch.group(0)!;
              debugPrint('📧 Extracted From email: $from');
            } else {
              debugPrint('⚠️ Could not extract email from From header: $headerValue');
              // Keep the original value as fallback
            }
          }
        } else if (headerName == 'to') {
          // Extract email address from To field
          // Handle multiple recipients separated by commas
          // Try angle brackets first: "Name <email@domain.com>"
          final angleBracketMatches = RegExp(r'<([\w\.-]+@[\w\.-]+\.\w+)>').allMatches(headerValue);
          if (angleBracketMatches.isNotEmpty) {
            // Get the first email from angle brackets
            to = angleBracketMatches.first.group(1)!;
            debugPrint('📧 Extracted To email from angle brackets: $to');
          } else {
            // Try to find email without angle brackets
            final emailMatch = RegExp(r'[\w\.-]+@[\w\.-]+\.\w+').firstMatch(headerValue);
            if (emailMatch != null) {
              to = emailMatch.group(0)!;
              debugPrint('📧 Extracted To email: $to');
            }
          }
        } else if (headerName == 'reply-to') {
          // Extract email address from Reply-To field
          final emailMatch = RegExp(r'[\w\.-]+@[\w\.-]+\.\w+').firstMatch(headerValue);
          if (emailMatch != null) {
            replyTo = emailMatch.group(0)!;
            debugPrint('📧 Extracted Reply-To email: $replyTo');
          }
        } else if (headerName == 'subject') {
          subject = headerValue;
        } else if (headerName == 'date') {
          try {
            date = DateTime.parse(headerValue);
          } catch (e) {
            // Keep default date
          }
        }
      }
      
      debugPrint('📧 Final parsed email - From: $from, To: $to, Reply-To: $replyTo');
      
      // Extract body
      if (message.payload?.body?.data != null) {
        body = utf8.decode(base64Url.decode(message.payload!.body!.data!));
      } else if (message.payload?.parts != null) {
        for (final part in message.payload!.parts!) {
          if (part.mimeType == 'text/plain' && part.body?.data != null) {
            body = utf8.decode(base64Url.decode(part.body!.data!));
            break;
          }
        }
      }
      
      // Extract attachments (handle nested parts)
      _extractAttachments(message.payload, attachments, message.id ?? '');
      
      return EmailMessage(
        id: message.id ?? '',
        from: from,
        to: to,
        replyTo: replyTo,
        subject: subject,
        body: body,
        date: date,
        attachments: attachments,
      );
    } catch (e) {
      debugPrint('Error parsing Gmail message: $e');
      return EmailMessage(
        id: message.id ?? '',
        from: 'unknown',
        subject: 'Parse Error',
        body: '',
        date: DateTime.now(),
      );
    }
  }

  /// Recursively extract attachments from message parts
  void _extractAttachments(gmail.MessagePart? payload, List<EmailAttachment> attachments, String messageId) {
    if (payload == null) return;
    
    // Check if this part is an attachment
    if (payload.filename != null && payload.filename!.isNotEmpty) {
      final fileName = payload.filename!;
      if (fileName.toLowerCase().endsWith('.pdf') || 
          fileName.toLowerCase().endsWith('.doc') ||
          fileName.toLowerCase().endsWith('.docx')) {
        // Store attachment ID for later fetching
        final attachmentId = payload.body?.attachmentId;
        attachments.add(EmailAttachment(
          name: fileName,
          data: attachmentId != null ? Uint8List(0) : (payload.body?.data != null ? base64Url.decode(payload.body!.data!) : Uint8List(0)),
          contentType: payload.mimeType ?? 'application/octet-stream',
          attachmentId: attachmentId,
          messageId: messageId,
        ));
      }
    }
    
    // Recursively check nested parts
    if (payload.parts != null) {
      for (final part in payload.parts!) {
        _extractAttachments(part, attachments, messageId);
      }
    }
  }

  /// Fetch attachment data for an email message
  Future<Uint8List> fetchAttachmentData(String messageId, String attachmentId) async {
    try {
      // Ensure Gmail API is initialized
      if (_gmailApi == null) {
        debugPrint('⚠️ Gmail API is null, attempting to initialize...');
        await _initializeGmailApi(silent: false);
      }
      
      if (_gmailApi == null) {
        throw Exception('Gmail API not initialized. Please sign in with Gmail to fetch attachments.');
      }
      
      final attachment = await _gmailApi!.users.messages.attachments.get(
        'me',
        messageId,
        attachmentId,
      );
      
      if (attachment.data == null) {
        throw Exception('Attachment data is null');
      }
      
      return base64Url.decode(attachment.data!);
    } catch (e) {
      debugPrint('Error fetching attachment: $e');
      rethrow;
    }
  }

  /// Send email with attachment using SMTP
  Future<bool> sendEmailWithAttachment({
    required String to,
    required String subject,
    required String body,
    required String attachmentName,
    required Uint8List attachmentData,
    String? replyTo,
  }) async {
    try {
      debugPrint('📤 Sending email to $to...');
      
      final password = await getEmailPassword();
      if (password == null || password.isEmpty) {
        throw Exception(
          'Email app password not configured. Please set it in settings.\n'
          'For Gmail, generate an app password: https://myaccount.google.com/apppasswords'
        );
      }

      // Create SMTP server
      final smtpServer = SmtpServer(
        AppConstants.smtpHost,
        port: AppConstants.smtpPort,
        ssl: false,
        allowInsecure: false,
        username: AppConstants.emailAddress,
        password: password,
      );

      // Create message
      final message = Message()
        ..from = Address(AppConstants.emailAddress, 'PO Processor')
        ..recipients.add(to)
        ..subject = subject
        ..html = body
        ..attachments = [
          StreamAttachment(
            Stream.value(attachmentData),
            attachmentName,
          ),
        ];

      // Send email
      final sendReport = await send(message, smtpServer);
      debugPrint('✅ Email sent successfully: ${sendReport.toString()}');
      return true;
    } catch (e) {
      debugPrint('❌ Error sending email: $e');
      rethrow;
    }
  }

  /// Send quotation email to customer using Gmail API (direct send, no mail client)
  Future<bool> sendQuotationEmail({
    required String to,
    required String quotationNumber,
    required Uint8List quotationPdf,
    String? customerName,
    required List<Map<String, dynamic>> items, // List of items with name, quantity, unitPrice, total
    required double grandTotal,
    String? currency,
  }) async {
    try {
      // Ensure Gmail API is initialized
      if (_gmailApi == null) {
        try {
          await _initializeGmailApi(silent: true);
        } catch (e) {
          debugPrint('⚠️ Silent initialization failed, trying interactive...');
          await _initializeGmailApi(silent: false);
        }
      }
      
      if (_gmailApi == null) {
        throw Exception('Gmail API not initialized. Please sign in with Gmail to send emails.');
      }
      
      final currencyCode = currency ?? 'AED';
      final customerNameText = customerName ?? 'Valued Customer';
      
      // Build subject
      final subject = 'Quotation $quotationNumber';
      
      // Build email body with matched items and grand total
      final StringBuffer bodyBuffer = StringBuffer();
      bodyBuffer.writeln('Dear $customerNameText,');
      bodyBuffer.writeln('');
      bodyBuffer.writeln('Thank you for your inquiry. Please find below our quotation details:');
      bodyBuffer.writeln('');
      bodyBuffer.writeln('Quotation Number: $quotationNumber');
      bodyBuffer.writeln('');
      bodyBuffer.writeln('Items:');
      
      // Add matched items
      for (final item in items) {
        final itemName = item['itemName'] as String? ?? '';
        final quantity = item['quantity'] as double? ?? 0.0;
        final unit = item['unit'] as String? ?? 'EA';
        final unitPrice = item['unitPrice'] as double? ?? 0.0;
        final lineTotal = item['total'] as double? ?? 0.0;
        
        if (unitPrice > 0) {
          bodyBuffer.writeln('• $itemName: $quantity $unit × $currencyCode ${unitPrice.toStringAsFixed(2)} = $currencyCode ${lineTotal.toStringAsFixed(2)}');
        }
      }
      
      bodyBuffer.writeln('');
      bodyBuffer.writeln('Grand Total: $currencyCode ${grandTotal.toStringAsFixed(2)}');
      bodyBuffer.writeln('');
      bodyBuffer.writeln('We look forward to your response.');
      bodyBuffer.writeln('');
      bodyBuffer.writeln('Best regards,');
      bodyBuffer.writeln('PO Processor Team');
      
      final body = bodyBuffer.toString();
      
      // Encode the PDF attachment in base64
      final pdfBase64 = base64Encode(quotationPdf);
      
      // Create email message in RFC 2822 format
      final emailMessage = [
        'To: $to',
        'Subject: $subject',
        'Content-Type: multipart/mixed; boundary="boundary123"',
        '',
        '--boundary123',
        'Content-Type: text/plain; charset=UTF-8',
        '',
        body,
        '',
        '--boundary123',
        'Content-Type: application/pdf; name="Quotation_${quotationNumber}.pdf"',
        'Content-Disposition: attachment; filename="Quotation_${quotationNumber}.pdf"',
        'Content-Transfer-Encoding: base64',
        '',
        pdfBase64,
        '',
        '--boundary123--',
      ].join('\r\n');
      
      // Encode the message in base64url format (Gmail API requirement)
      final encodedMessage = base64Url.encode(utf8.encode(emailMessage));
      
      // Create Gmail message
      final message = gmail.Message(
        raw: encodedMessage,
      );
      
      // Send the email via Gmail API
      final sentMessage = await _gmailApi!.users.messages.send(message, 'me');
      
      if (sentMessage.id != null) {
        debugPrint('✅ Quotation email sent successfully via Gmail API. Message ID: ${sentMessage.id}');
        return true;
      } else {
        throw Exception('Failed to send email: No message ID returned');
      }
    } catch (e) {
      debugPrint('❌ Error sending quotation email via Gmail API: $e');
      rethrow;
    }
  }

  /// Check if email is configured
  Future<bool> isEmailConfigured() async {
    final password = await getEmailPassword();
    return password != null && password.isNotEmpty;
  }
}

/// Custom HTTP client that adds authentication headers
class _AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Map<String, String> _headers;

  _AuthenticatedHttpClient(this._inner, this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    _headers.forEach((key, value) {
      request.headers[key] = value;
    });
    return _inner.send(request);
  }
}

/// Email message model
class EmailMessage {
  final String id;
  final String from;
  final String? to;
  final String? replyTo;
  final String subject;
  final String body;
  final DateTime date;
  final List<EmailAttachment> attachments;

  EmailMessage({
    required this.id,
    required this.from,
    this.to,
    this.replyTo,
    required this.subject,
    required this.body,
    required this.date,
    this.attachments = const [],
  });
}

/// Email attachment model
class EmailAttachment {
  final String name;
  final Uint8List data;
  final String contentType;
  final String? attachmentId;
  final String? messageId;

  EmailAttachment({
    required this.name,
    required this.data,
    required this.contentType,
    this.attachmentId,
    this.messageId,
  });
}

