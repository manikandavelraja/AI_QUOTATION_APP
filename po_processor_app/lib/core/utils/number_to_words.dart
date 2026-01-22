/// Utility class to convert numbers to words
class NumberToWords {
  static const List<String> ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen'
  ];

  static const List<String> tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety'
  ];

  /// Convert number to words (for AED/Dirhams)
  static String convertToWords(double amount, {String currency = 'AED'}) {
    final wholePart = amount.toInt();
    final decimalPart = ((amount - wholePart) * 100).round();
    
    String words = _convertNumber(wholePart);
    
    if (currency.toUpperCase() == 'AED') {
      words += ' Dirham${wholePart != 1 ? 's' : ''}';
    } else if (currency.toUpperCase() == 'USD') {
      words += ' Dollar${wholePart != 1 ? 's' : ''}';
    } else if (currency.toUpperCase() == 'INR') {
      words += ' Rupee${wholePart != 1 ? 's' : ''}';
    } else {
      words += ' ${currency}';
    }
    
    if (decimalPart > 0) {
      words += ' and ${_convertNumber(decimalPart)} Cent${decimalPart != 1 ? 's' : ''}';
    }
    
    return words;
  }

  static String _convertNumber(int number) {
    if (number == 0) return 'Zero';
    if (number < 20) return ones[number];
    if (number < 100) {
      final tensDigit = number ~/ 10;
      final onesDigit = number % 10;
      if (onesDigit == 0) {
        return tens[tensDigit];
      }
      return '${tens[tensDigit]}-${ones[onesDigit]}';
    }
    if (number < 1000) {
      final hundreds = number ~/ 100;
      final remainder = number % 100;
      if (remainder == 0) {
        return '${ones[hundreds]} Hundred';
      }
      return '${ones[hundreds]} Hundred ${_convertNumber(remainder)}';
    }
    if (number < 100000) {
      final thousands = number ~/ 1000;
      final remainder = number % 1000;
      if (remainder == 0) {
        return '${_convertNumber(thousands)} Thousand';
      }
      return '${_convertNumber(thousands)} Thousand ${_convertNumber(remainder)}';
    }
    if (number < 1000000) {
      final lakhs = number ~/ 100000;
      final remainder = number % 100000;
      if (remainder == 0) {
        return '${_convertNumber(lakhs)} Lakh';
      }
      return '${_convertNumber(lakhs)} Lakh ${_convertNumber(remainder)}';
    }
    // For millions and above
    final millions = number ~/ 1000000;
    final remainder = number % 1000000;
    if (remainder == 0) {
      return '${_convertNumber(millions)} Million';
    }
    return '${_convertNumber(millions)} Million ${_convertNumber(remainder)}';
  }
}

