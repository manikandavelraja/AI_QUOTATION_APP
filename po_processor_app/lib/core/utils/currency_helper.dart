class CurrencyHelper {
  /// Get currency symbol based on currency code
  static String getCurrencySymbol(String? currencyCode) {
    if (currencyCode == null || currencyCode.isEmpty) {
      return '₹'; // Default to INR
    }
    
    final code = currencyCode.toUpperCase();
    switch (code) {
      case 'INR':
        return '₹';
      case 'AED':
        return 'AED ';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'SAR':
        return 'SAR ';
      case 'QAR':
        return 'QAR ';
      case 'KWD':
        return 'KWD ';
      case 'OMR':
        return 'OMR ';
      case 'BHD':
        return 'BHD ';
      default:
        return '$code '; // Return code if symbol not found
    }
  }
  
  /// Format amount with currency symbol
  static String formatAmount(double amount, String? currencyCode) {
    final symbol = getCurrencySymbol(currencyCode);
    return '$symbol${amount.toStringAsFixed(2)}';
  }
  
  /// Get currency code from symbol or text
  static String? detectCurrency(String text) {
    final upperText = text.toUpperCase();
    
    // Check for currency codes
    if (upperText.contains('AED') || upperText.contains('DIRHAM')) {
      return 'AED';
    } else if (upperText.contains('INR') || upperText.contains('₹') || upperText.contains('RUPEE')) {
      return 'INR';
    } else if (upperText.contains('USD') || upperText.contains('\$') || upperText.contains('DOLLAR')) {
      return 'USD';
    } else if (upperText.contains('EUR') || upperText.contains('€') || upperText.contains('EURO')) {
      return 'EUR';
    } else if (upperText.contains('GBP') || upperText.contains('£') || upperText.contains('POUND')) {
      return 'GBP';
    } else if (upperText.contains('SAR')) {
      return 'SAR';
    } else if (upperText.contains('QAR')) {
      return 'QAR';
    } else if (upperText.contains('KWD')) {
      return 'KWD';
    } else if (upperText.contains('OMR')) {
      return 'OMR';
    } else if (upperText.contains('BHD')) {
      return 'BHD';
    }
    
    return null;
  }
}


