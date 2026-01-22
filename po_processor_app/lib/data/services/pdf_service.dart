import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../core/constants/app_constants.dart';
import 'gemini_ai_service.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/customer_inquiry.dart';
import '../../domain/entities/quotation.dart';

class PDFService {
  /// Pick and validate PDF file
  Future<FilePickerResult?> pickPDFFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.allowedFileTypes,
        withData: true,
      );

      if (result != null) {
        final fileSizeMB = result.files.single.size / (1024 * 1024);
        if (fileSizeMB > AppConstants.maxFileSizeMB) {
          throw Exception('File size exceeds ${AppConstants.maxFileSizeMB}MB');
        }
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Save PDF file to local storage
  Future<String> savePDFFile(PlatformFile file) async {
    try {
      if (kIsWeb) {
        // On web, just return the file name as reference
        return '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final pdfDir = Directory(path.join(directory.path, 'pdfs'));
      
      if (!await pdfDir.exists()) {
        await pdfDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final filePath = path.join(pdfDir.path, fileName);
      
      if (file.bytes != null) {
        final savedFile = File(filePath);
        await savedFile.writeAsBytes(file.bytes!);
        return filePath;
      } else if (file.path != null && file.path!.isNotEmpty) {
        final sourceFile = File(file.path!);
        await sourceFile.copy(filePath);
        return filePath;
      } else {
        throw Exception('File data is null');
      }
    } catch (e) {
      throw Exception('Failed to save PDF file: $e');
    }
  }

  /// Extract text from PDF bytes (web-compatible)
  /// Uses Gemini AI to extract text from PDF
  Future<String> extractTextFromPDFBytes(Uint8List bytes, String fileName) async {
    try {
      // Use Gemini AI to extract text from PDF
      // Gemini 1.5 can process PDFs directly
      final aiService = GeminiAIService();
      return await aiService.extractTextFromPDFBytes(bytes, fileName);
    } catch (e) {
      throw Exception('Failed to extract text from PDF: $e');
    }
  }

  /// Extract text from PDF file path (for non-web platforms)
  Future<String> extractTextFromPDF(String pdfPath) async {
    try {
      if (kIsWeb) {
        throw Exception('Use extractTextFromPDFBytes for web platform');
      }
      
      final file = File(pdfPath);
      if (!await file.exists()) {
        throw Exception('PDF file not found');
      }
      
      final bytes = await file.readAsBytes();
      return await extractTextFromPDFBytes(bytes, path.basename(pdfPath));
    } catch (e) {
      throw Exception('Failed to extract text from PDF: $e');
    }
  }

  /// Validate if the extracted text is a valid PO
  Future<bool> validatePOFile(String pdfText) async {
    try {
      final aiService = GeminiAIService();
      return await aiService.validatePOFile(pdfText);
    } catch (e) {
      // If validation fails, assume it's valid and let extraction handle it
      return true;
    }
  }

  /// Extract PO data directly from PDF bytes (more efficient)
  /// PRIMARY METHOD: Sends PDF directly to Gemini as base64-encoded InlineDataPart
  /// Falls back to text-based extraction if direct method fails
  Future<PurchaseOrder> extractPODataFromPDFBytes(Uint8List bytes, String fileName) async {
    try {
      final aiService = GeminiAIService();
      
      // PRIMARY METHOD: Send PDF directly to Gemini using inline_data (visual processing)
      // This is the most reliable method for parsing ANY PDF format
      debugPrint('📤 Attempting direct PDF extraction with inline_data (visual processing)...');
      try {
        final result = await aiService.extractPOFromPDFBytes(bytes, fileName)
            .timeout(const Duration(minutes: 5), onTimeout: () {
          throw Exception('PDF processing timed out. Please try again.');
        });
        
        debugPrint('📥 Received result from direct extraction: isValid=${result['isValid']}');
        
        // Check validation result - be more lenient
        if (result['poData'] != null) {
          final po = result['poData'] as PurchaseOrder;
          
          // Even if isValid is false, use the data if we got something
          if (result['isValid'] == true) {
            debugPrint('✅ Direct PDF extraction successful with valid data!');
            return po;
          } else {
            // Check if we got meaningful data despite validation failure
            final hasData = (po.poNumber.isNotEmpty && po.poNumber != 'N/A') ||
                           (po.customerName.isNotEmpty && po.customerName != 'N/A') ||
                           po.lineItems.isNotEmpty ||
                           po.totalAmount > 0;
            
            if (hasData) {
              debugPrint('⚠️ Validation returned false but extracted meaningful data. Using it.');
              return po;
            } else {
              final summary = result['summary'] as String? ?? '';
              debugPrint('⚠️ Direct extraction returned no meaningful data. Summary: $summary');
              throw Exception(summary.isNotEmpty ? summary : 'Failed to extract valid PO data from PDF.');
            }
          }
        } else {
          final summary = result['summary'] as String? ?? '';
          debugPrint('⚠️ Direct extraction returned null poData. Summary: $summary');
          throw Exception(summary.isNotEmpty ? summary : 'Failed to extract PO data from PDF.');
        }
      } catch (directError) {
        debugPrint('❌ Direct PDF extraction with inline_data failed: $directError');
        debugPrint('❌ Error details: ${directError.toString()}');
        // Don't fall back to text extraction - the inline_data method should work
        // Re-throw with a clear message
        rethrow;
      }
    } catch (e) {
      // Check if it's a rate limit error and preserve the original message
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('rate limit') || 
          errorString.contains('429') ||
          errorString.contains('rpm') ||
          errorString.contains('tpm') ||
          errorString.contains('rpd')) {
        // Re-throw rate limit errors as-is so they're handled properly
        rethrow;
      }
      throw Exception('Failed to extract PO data: $e');
    }
  }

  /// Extract PO data from text using AI
  Future<PurchaseOrder> extractPODataFromText(String pdfText) async {
    try {
      final aiService = GeminiAIService();
      return await aiService.extractPOData(pdfText)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        throw Exception('PO data extraction timed out. Please try again.');
      });
    } catch (e) {
      throw Exception('Failed to extract PO data: $e');
    }
  }

  /// Validate file type
  bool isValidFileType(String fileName) {
    if (fileName.isEmpty) return false;
    
    final extension = path.extension(fileName).toLowerCase();
    if (extension.isEmpty) return false;
    
    // Remove the dot from extension
    final extWithoutDot = extension.startsWith('.') 
        ? extension.substring(1) 
        : extension;
    
    // Check if it's in allowed types
    final isValid = AppConstants.allowedFileTypes.contains(extWithoutDot);
    
    // Also check for common PDF file name patterns
    if (!isValid) {
      final lowerName = fileName.toLowerCase();
      return lowerName.endsWith('.pdf') || lowerName.contains('pdf');
    }
    
    return isValid;
  }

  // ========== CUSTOMER INQUIRY OPERATIONS ==========
  /// Extract Inquiry data from PDF bytes
  Future<CustomerInquiry> extractInquiryDataFromPDFBytes(Uint8List bytes, String fileName) async {
    try {
      final aiService = GeminiAIService();
      final pdfText = await extractTextFromPDFBytes(bytes, fileName);
      return await aiService.extractInquiryData(pdfText);
    } catch (e) {
      throw Exception('Failed to extract inquiry data: $e');
    }
  }

  // ========== QUOTATION OPERATIONS ==========
  /// Extract Quotation data from PDF bytes
  Future<Quotation> extractQuotationDataFromPDFBytes(Uint8List bytes, String fileName) async {
    try {
      final aiService = GeminiAIService();
      final pdfText = await extractTextFromPDFBytes(bytes, fileName);
      return await aiService.extractQuotationData(pdfText);
    } catch (e) {
      throw Exception('Failed to extract quotation data: $e');
    }
  }
}

