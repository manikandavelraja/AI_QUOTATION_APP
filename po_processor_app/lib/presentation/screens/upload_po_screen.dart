import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../data/services/pdf_service.dart';
import '../../data/services/email_service.dart';
import '../providers/po_provider.dart';
import '../../core/theme/app_theme.dart';

class UploadPOScreen extends ConsumerStatefulWidget {
  const UploadPOScreen({super.key});

  @override
  ConsumerState<UploadPOScreen> createState() => _UploadPOScreenState();
}

class _UploadPOScreenState extends ConsumerState<UploadPOScreen> with SingleTickerProviderStateMixin {
  final _pdfService = PDFService();
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

  Future<void> _getPOFromMail() async {
    try {
      setState(() {
        _isFetchingEmail = true;
        _errorMessage = null;
        _selectedFilePath = null;
      });

      ref.read(poProvider.notifier).clearError();

      // Fetch PO emails directly via Gmail API (will prompt for sign-in if needed)
      final emails = await _emailService.fetchPOEmails();

      if (emails.isEmpty) {
        setState(() {
          _isFetchingEmail = false;
          _errorMessage = 'No PO emails found in inbox';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No PO emails found in inbox'),
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

      // Process the selected PO email with PDF attachment
      final poEmail = selectedEmail!;
      final pdfAttachment = poEmail.attachments.firstWhere(
        (att) => att.name.toLowerCase().endsWith('.pdf'),
        orElse: () => throw Exception('No PO PDF attachment found in email'),
      );

      // Fetch attachment data if not already loaded
      Uint8List pdfData;
      if (pdfAttachment.data.isEmpty && pdfAttachment.attachmentId != null && pdfAttachment.messageId != null) {
        // Need to fetch attachment data from Gmail API
        pdfData = await _emailService.fetchAttachmentData(pdfAttachment.messageId!, pdfAttachment.attachmentId!);
      } else {
        pdfData = pdfAttachment.data;
      }

      // Process the PO PDF
      await _processPOFromEmail(pdfData, pdfAttachment.name);
    } catch (e) {
      setState(() {
        _isFetchingEmail = false;
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        _errorMessage = errorMsg;
      });

      if (mounted && _errorMessage != null) {
        if (_errorMessage!.contains('sign in') || _errorMessage!.contains('authentication')) {
          // Show sign-in dialog
          _showGmailSignInDialog();
        } else {
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
  }

  Future<EmailMessage?> _showEmailSelectionDialog(List<EmailMessage> emails) async {
    return showDialog<EmailMessage>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select PO Email'),
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

  void _showGmailSignInDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email, color: Colors.blue),
            SizedBox(width: 8),
            Text('Gmail Sign-In Required'),
          ],
        ),
        content: const Text(
          'To fetch PO emails, you need to sign in with your Gmail account.\n\n'
          'This will allow the app to access your inbox to fetch purchase orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Retry fetching (will trigger sign-in)
              _getPOFromMail();
            },
            child: const Text('Sign In with Gmail'),
          ),
        ],
      ),
    );
  }

  Future<void> _processPOFromEmail(Uint8List pdfBytes, String fileName) async {
    try {
      setState(() {
        _isProcessing = true;
        _isFetchingEmail = false;
        _selectedFilePath = fileName;
      });

      // Extract PO data from PDF
      final po = await _pdfService.extractPODataFromPDFBytes(pdfBytes, fileName);

      // Save PDF file
      final platformFile = PlatformFile(
        name: fileName,
        bytes: pdfBytes,
        size: pdfBytes.length,
        path: null,
      );
      final savedPath = await _pdfService.savePDFFile(platformFile);
      final finalPO = po.copyWith(pdfPath: savedPath);

      // Save to database
      final savedPO = await ref.read(poProvider.notifier).addPurchaseOrder(finalPO);

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
                Text('PO fetched from email and processed successfully'),
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
          if (mounted && savedPO?.id != null) {
            context.go('/po-detail/${savedPO!.id}');
          } else if (mounted) {
            context.go('/dashboard');
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

  Future<void> _pickAndProcessPDF() async {
    try {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
        _selectedFilePath = null;
      });

      ref.read(poProvider.notifier).clearError();
      
      final result = await _pdfService.pickPDFFile();
      
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final file = result.files.single;
      
      if (!_pdfService.isValidFileType(file.name)) {
        throw Exception('invalid_file_type'.tr());
      }
      
      _selectedFilePath = file.name;

      if (file.bytes == null) {
        throw Exception('File data is not available. Please try again.');
      }

      final po = await _pdfService.extractPODataFromPDFBytes(file.bytes!, file.name);
      
      final savedPath = await _pdfService.savePDFFile(file);
      final finalPO = po.copyWith(pdfPath: savedPath);
      
      final savedPO = await ref.read(poProvider.notifier).addPurchaseOrder(finalPO);

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
                Text('file_uploaded'.tr()),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        // Redirect to PO detail screen to show parsed data
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && savedPO?.id != null) {
            context.go('/po-detail/${savedPO!.id}');
          } else if (mounted) {
            // Fallback to dashboard if ID is not available
            context.go('/dashboard');
          }
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('rate limit') || 
            errorString.contains('429') ||
            errorString.contains('too many requests') ||
            errorString.contains('quota') ||
            errorString.contains('rpm') ||
            errorString.contains('tpm') ||
            errorString.contains('rpd') ||
            errorString.contains('per minute') ||
            errorString.contains('per day')) {
          String errorType = '';
          if (errorString.contains('rpm') || errorString.contains('requests per minute')) {
            errorType = ' (RPM - Requests Per Minute limit reached)';
          } else if (errorString.contains('tpm') || errorString.contains('tokens per minute')) {
            errorType = ' (TPM - Tokens Per Minute limit reached)';
          } else if (errorString.contains('rpd') || errorString.contains('requests per day')) {
            errorType = ' (RPD - Daily request limit reached)';
          }
          
          final waitTimeMatch = RegExp(r'wait (\d+) seconds').firstMatch(e.toString());
          if (waitTimeMatch != null) {
            final waitSeconds = waitTimeMatch.group(1);
            _errorMessage = 'API rate limit exceeded$errorType. Please wait $waitSeconds seconds and try again.';
          } else if (errorString.contains('per day') || errorString.contains('rpd')) {
            _errorMessage = 'Daily API request limit reached$errorType. Please try again tomorrow or upgrade your API plan.';
          } else {
            _errorMessage = 'API rate limit exceeded$errorType. Please wait a few moments and try again. The AI service has limits on requests per minute.';
          }
        } else if (errorString.contains('timeout')) {
          if (errorString.contains('rate limit') || errorString.contains('rate limits')) {
            _errorMessage = 'Request timed out due to API rate limits. Please wait a few moments and try again.';
          } else {
            _errorMessage = 'Request timed out. Please try again.';
          }
        } else if (errorString.contains('corrupted') || errorString.contains('image-based')) {
          _errorMessage = 'Failed to extract text from PDF. The PDF may be corrupted or image-based. Please ensure the PDF contains selectable text.';
        } else {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        }
      });

      if (mounted && _errorMessage != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryGreen,
                AppTheme.primaryGreenLight,
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'upload_po'.tr(),
          style: const TextStyle(
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
                  AppTheme.primaryGreen.withOpacity(0.1),
                  AppTheme.primaryGreenLight.withOpacity(0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 64,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'upload_pdf'.tr(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'select_file'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
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
                onTap: (_isFetchingEmail || _isProcessing) ? null : _getPOFromMail,
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
                            color: Colors.grey[600],
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
                  AppTheme.primaryGreen,
                  AppTheme.primaryGreenLight,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryGreen.withOpacity(0.3),
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
                        _isProcessing ? 'processing'.tr() : 'select_file'.tr(),
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
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'extracting_data'.tr(),
                  style: TextStyle(
                    color: Colors.grey[600],
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                  if (_errorMessage!.toLowerCase().contains('rate limit') ||
                      _errorMessage!.toLowerCase().contains('rpm') ||
                      _errorMessage!.toLowerCase().contains('tpm') ||
                      _errorMessage!.toLowerCase().contains('rpd') ||
                      _errorMessage!.toLowerCase().contains('429') ||
                      _errorMessage!.toLowerCase().contains('quota')) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _pickAndProcessPDF,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                'instructions'.tr(),
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
            'instruction_1'.tr(),
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildInstructionItem(
            context,
            Icons.check_circle,
            'instruction_2'.tr(),
            Colors.green,
          ),
          const SizedBox(height: 12),
          _buildInstructionItem(
            context,
            Icons.check_circle,
            'instruction_3'.tr(),
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
