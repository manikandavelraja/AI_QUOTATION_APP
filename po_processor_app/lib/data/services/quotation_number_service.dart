import 'database_service.dart';

/// Service for generating quotation numbers with the format:
/// ALK [Date]-[Month]-[Year]-[6-Digit Serial]
/// Where the 6-digit serial must always be an even number (e.g., 100000, 100002, 100004)
class QuotationNumberService {
  final DatabaseService _databaseService;

  QuotationNumberService(this._databaseService);

  /// Generate the next quotation number
  /// Format: ALK DD-MM-YYYY-XXXXXX (e.g., ALK 15-03-2024-100000)
  /// Serial numbers are always even: 100000, 100002, 100004, etc.
  Future<String> generateNextQuotationNumber() async {
    final now = DateTime.now();
    final date = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = now.year.toString();

    // Get all quotations to find the highest serial number for today's date
    final allQuotations = await _databaseService.getAllQuotations();
    
    // Extract serial numbers from existing quotations that match today's date format
    final todayPrefix = 'ALK $date-$month-$year-';
    
    int maxSerial = 99998; // Start below 100000 so we can detect if any exist
    
    for (final quotation in allQuotations) {
      final qtnNumber = quotation.quotationNumber.trim();
      
      // Check if quotation number matches today's format: ALK DD-MM-YYYY-XXXXXX
      if (qtnNumber.startsWith(todayPrefix)) {
        try {
          // Extract the serial number part (after the date prefix)
          // Format: ALK DD-MM-YYYY-XXXXXX
          final serialStr = qtnNumber.substring(todayPrefix.length).trim();
          
          // Validate it's exactly 6 digits
          if (serialStr.length == 6) {
            final serial = int.tryParse(serialStr);
            if (serial != null && serial >= 100000 && serial > maxSerial) {
              maxSerial = serial;
            }
          }
        } catch (e) {
          // Skip invalid format
          continue;
        }
      }
    }
    
    // Generate next even serial number
    // Start with 100000 if no previous serials found for today
    int nextSerial;
    if (maxSerial < 100000) {
      // No quotations found for today, start with 100000
      nextSerial = 100000;
    } else if (maxSerial % 2 == 0) {
      // Last serial was even, add 2 to get next even number
      nextSerial = maxSerial + 2;
    } else {
      // Last serial was odd, add 1 to make it even
      nextSerial = maxSerial + 1;
    }
    
    // Ensure we don't exceed 6 digits (max 999998, but we'll cap at 999998 for safety)
    if (nextSerial > 999998) {
      nextSerial = 999998;
    }
    
    // Format serial as 6-digit string
    final serialStr = nextSerial.toString().padLeft(6, '0');
    
    // Return formatted quotation number: ALK DD-MM-YYYY-XXXXXX
    final quotationNumber = 'ALK $date-$month-$year-$serialStr';
    
    return quotationNumber;
  }
}

