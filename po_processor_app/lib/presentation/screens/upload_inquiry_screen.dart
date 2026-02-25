import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/services/pdf_service.dart';
import '../../data/services/gemini_ai_service.dart';
import '../../data/services/email_service.dart';
import '../providers/inquiry_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/customer_inquiry.dart';

class UploadInquiryScreen extends ConsumerStatefulWidget {
  const UploadInquiryScreen({super.key});

  @override
  ConsumerState<UploadInquiryScreen> createState() => _UploadInquiryScreenState();
}

class _UploadInquiryScreenState extends ConsumerState<UploadInquiryScreen> with SingleTickerProviderStateMixin {
  final _pdfService = PDFService();
  final _aiService = GeminiAIService();
  final _emailService = EmailService();
  bool _isProcessing = false;
  bool _isFetchingEmail = false;
  String? _errorMessage;
  String? _selectedFilePath;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _getFromMail() async {
    try {
      setState(() {
        _isFetchingEmail = true;
        _errorMessage = null;
        _selectedFilePath = null;
      });

      ref.read(inquiryProvider.notifier).clearError();

      // Fetch emails directly via Gmail API (will prompt for sign-in if needed)
      final emails = await _emailService.fetchInquiryEmails();

      if (emails.isEmpty) {
        setState(() {
          _isFetchingEmail = false;
          _errorMessage = 'No inquiry emails found in inbox';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No inquiry emails found in inbox'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Show email selection dialog if multiple emails
      EmailMessage? selectedEmail;
      if (emails.length > 1) {
        if (mounted) {
          selectedEmail = await _showEmailSelectionDialog(emails);
          if (selectedEmail == null) {
            setState(() => _isFetchingEmail = false);
            return;
          }
        }
      } else {
        selectedEmail = emails.first;
      }

      // Process the selected email's attachment
      if (selectedEmail != null) {
        await _processEmailAttachment(selectedEmail);
      }
    } catch (e) {
      setState(() {
        _isFetchingEmail = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });

      if (mounted && _errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _processEmailAttachment(EmailMessage email) async {
    try {
      setState(() {
        _isProcessing = true;
        _isFetchingEmail = false;
      });

      // Find PDF or DOC attachment
      final pdfAttachment = email.attachments.firstWhere(
        (att) => att.name.toLowerCase().endsWith('.pdf') || 
                 att.name.toLowerCase().endsWith('.doc') ||
                 att.name.toLowerCase().endsWith('.docx'),
        orElse: () => throw Exception('No PDF or DOC attachment found in email'),
      );

      _selectedFilePath = pdfAttachment.name;

      // Fetch attachment data if not already loaded
      Uint8List pdfData;
      if (pdfAttachment.data.isEmpty && pdfAttachment.attachmentId != null && pdfAttachment.messageId != null) {
        // Need to fetch attachment data from Gmail API
        pdfData = await _emailService.fetchAttachmentData(pdfAttachment.messageId!, pdfAttachment.attachmentId!);
      } else {
        pdfData = pdfAttachment.data;
      }

      // Extract inquiry data directly from PDF bytes (visual processing)
      CustomerInquiry inquiry;
      if (pdfAttachment.name.toLowerCase().endsWith('.pdf')) {
        inquiry = await _aiService.extractInquiryFromPDFBytes(pdfData, pdfAttachment.name);
      } else {
        // For DOC files, we'd need additional processing
        throw Exception('DOC file processing not yet implemented. Please use PDF files.');
      }

      // Save PDF file
      final platformFile = PlatformFile(
        name: pdfAttachment.name,
        bytes: pdfData,
        size: pdfData.length,
        path: null,
      );
      final savedPath = await _pdfService.savePDFFile(platformFile);
      final finalInquiry = inquiry.copyWith(pdfPath: savedPath);

      final savedInquiry = await ref.read(inquiryProvider.notifier).addInquiry(finalInquiry);

      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Inquiry fetched from email and processed successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && savedInquiry?.id != null) {
            context.go('/inquiry-detail/${savedInquiry!.id}');
          } else if (mounted) {
            context.go('/inquiry-list');
          }
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });

      if (mounted && _errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showEmailConfigDialog() async {
    final passwordController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'To fetch emails, you need to configure your Gmail app password.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Gmail App Password',
                hintText: 'Enter your Gmail app password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                // Open Gmail app password page
                // url_launcher would be used here
              },
              child: const Text('How to get app password?'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text.isNotEmpty) {
                await _emailService.setEmailPassword(passwordController.text);
                Navigator.pop(context);
                // Retry fetching emails
                _getFromMail();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<EmailMessage?> _showEmailSelectionDialog(List<EmailMessage> emails) async {
    return showDialog<EmailMessage>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Email'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: emails.length,
            itemBuilder: (context, index) {
              final email = emails[index];
              return ListTile(
                leading: const Icon(Icons.email),
                title: Text(
                  email.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'From: ${email.from}\n${email.attachments.length} attachment(s)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, email),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndProcessPDF() async {
    try {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
        _selectedFilePath = null;
      });

      ref.read(inquiryProvider.notifier).clearError();
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, // Ensure bytes are loaded for web compatibility
      );
      
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final file = result.files.single;
      
      if (!file.name.toLowerCase().endsWith('.pdf')) {
        throw Exception('Please select a PDF file');
      }
      
      _selectedFilePath = file.name;

      if (file.bytes == null) {
        throw Exception('File data is not available. Please try again.');
      }

      // Extract inquiry data directly from PDF bytes (visual processing)
      final inquiry = await _aiService.extractInquiryFromPDFBytes(file.bytes!, file.name);
      
      // Save PDF file
      // On web, file.path throws an exception when accessed, so we safely get it
      String? filePath;
      if (!kIsWeb) {
        try {
          filePath = file.path;
        } catch (e) {
          // Ignore if path is not available
          filePath = null;
        }
      }
      
      final platformFile = PlatformFile(
        name: file.name,
        bytes: file.bytes,
        size: file.size,
        path: filePath,
      );
      final savedPath = await _pdfService.savePDFFile(platformFile);
      final finalInquiry = inquiry.copyWith(pdfPath: savedPath);
      
      final savedInquiry = await ref.read(inquiryProvider.notifier).addInquiry(finalInquiry);

      setState(() {
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Inquiry uploaded successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && savedInquiry?.id != null) {
            context.go('/inquiry-detail/${savedInquiry!.id}');
          } else if (mounted) {
            context.go('/inquiry-list');
          }
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });

      if (mounted && _errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashboardBackground,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.iconGraphGreen,
                AppTheme.primaryGreenLight,
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Upload Customer Inquiry',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUploadCard(context),
                const SizedBox(height: 24),
                _buildInstructionsCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.iconGraphGreen.withOpacity(0.1),
                  AppTheme.primaryGreenLight.withOpacity(0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.upload_file,
              size: 64,
              color: AppTheme.iconGraphGreen,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Upload Inquiry PDF',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.iconGraphGreen,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a Customer Inquiry/RFQ PDF file',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // GetFromMail Button
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade600,
                  Colors.blue.shade400,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (_isFetchingEmail || _isProcessing) ? null : _getFromMail,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 18,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isFetchingEmail)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        const Icon(Icons.email, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        _isFetchingEmail ? 'Fetching...' : 'GetFromMail',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_selectedFilePath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFilePath!.split('/').last,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'File selected',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.iconGraphGreen,
                  AppTheme.primaryGreenLight,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.iconGraphGreen.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isProcessing ? null : _pickAndProcessPDF,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 18,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isProcessing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        const Icon(Icons.upload_file, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        _isProcessing ? 'Processing...' : 'Select File',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isProcessing) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.iconGraphGreen),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Extracting inquiry data...',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: Colors.red.shade900,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade50,
            Colors.blue.shade100.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.blue.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Instructions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInstructionItem(
            context,
            Icons.check_circle,
            'Upload a Customer Inquiry or RFQ (Request for Quotation) PDF',
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildInstructionItem(
            context,
            Icons.check_circle,
            'The system will extract inquiry number, customer details, and items',
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildInstructionItem(
            context,
            Icons.check_circle,
            'After extraction, you can create a quotation from this inquiry',
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

