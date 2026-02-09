import 'package:equatable/equatable.dart';

class MaterialForecast extends Equatable {
  final String materialCode;
  final String materialName;
  final double averageLeadTimeDays;
  final double consumptionRatePerMonth;
  final DateTime? predictedNextOrderDate;
  final String recommendation; // 'Stock' or 'Do Not Stock'
  final String recommendationReason;
  final List<PurchaseEvent> purchaseHistory;
  final double totalQuantityLast12Months;
  final int purchaseCountLast12Months;
  final double averageDaysBetweenPurchases;
  final double purchaseFrequencyConsistency; // 0-1 score

  const MaterialForecast({
    required this.materialCode,
    required this.materialName,
    required this.averageLeadTimeDays,
    required this.consumptionRatePerMonth,
    this.predictedNextOrderDate,
    required this.recommendation,
    required this.recommendationReason,
    required this.purchaseHistory,
    required this.totalQuantityLast12Months,
    required this.purchaseCountLast12Months,
    required this.averageDaysBetweenPurchases,
    required this.purchaseFrequencyConsistency,
  });

  @override
  List<Object?> get props => [
        materialCode,
        materialName,
        averageLeadTimeDays,
        consumptionRatePerMonth,
        predictedNextOrderDate,
        recommendation,
        recommendationReason,
        purchaseHistory,
        totalQuantityLast12Months,
        purchaseCountLast12Months,
        averageDaysBetweenPurchases,
        purchaseFrequencyConsistency,
      ];
}

class PurchaseEvent extends Equatable {
  final DateTime purchaseDate;
  final double quantity;
  final String unit;
  final String poNumber;
  final String? leadTimeDays; // Can be calculated or stored

  const PurchaseEvent({
    required this.purchaseDate,
    required this.quantity,
    required this.unit,
    required this.poNumber,
    this.leadTimeDays,
  });

  @override
  List<Object?> get props => [
        purchaseDate,
        quantity,
        unit,
        poNumber,
        leadTimeDays,
      ];
}

