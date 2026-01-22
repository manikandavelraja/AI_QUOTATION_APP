import 'package:flutter/foundation.dart';

/// Service for managing product catalog and price matching
class CatalogService {
  static final CatalogService _instance = CatalogService._internal();
  factory CatalogService() => _instance;
  CatalogService._internal();

  /// Product catalog with keyword -> price mapping
  /// Key: Product keyword (uppercase)
  /// Value: Unit price
  static const Map<String, double> productCatalog = {
    'WATER TAP': 37.0,
    'PIPE': 20.0,
  };

  /// Match item description to catalog and return unit price
  /// Returns the matched price or 0.0 if no match found
  double matchItemPrice(String itemName, {String? description}) {
    // Combine itemName and description for matching
    final searchText = '$itemName ${description ?? ''}'.trim().toUpperCase();
    
    if (searchText.isEmpty) {
      return 0.0;
    }

    // Check each catalog entry
    for (final entry in productCatalog.entries) {
      final keyword = entry.key;
      final price = entry.value;
      
      // If description contains the keyword, return the price
      if (searchText.contains(keyword)) {
        debugPrint('✅ Catalog match found: "$keyword" -> $price for "$searchText"');
        return price;
      }
    }

    // No match found
    debugPrint('⚠️ No catalog match for: "$searchText"');
    return 0.0;
  }

  /// Check if all items in a list have been matched (price > 0)
  bool areAllItemsMatched(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return false;
    
    for (final item in items) {
      final unitPrice = item['unitPrice'] as double? ?? 0.0;
      if (unitPrice <= 0.0) {
        return false;
      }
    }
    return true;
  }

  /// Get catalog entries for display
  Map<String, double> getCatalog() {
    return Map.from(productCatalog);
  }
}

