import 'package:flutter/material.dart';
import '../../data/services/vbelt_prediction_service.dart';

/// Shared recommendation model used by Seasonal Trends and Overall Recommendation.
class PlanningRecommendation {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String priority;
  final String category;

  PlanningRecommendation({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.priority,
    required this.category,
  });
}

/// Generates recommendations from Seasonal Trends prediction data.
List<PlanningRecommendation> generateSeasonalRecommendations(
  PredictionResult prediction,
) {
  final recommendations = <PlanningRecommendation>[];
  final region = prediction.region;
  final season = prediction.season;
  final weather = prediction.weatherData;

  if (prediction.predictedDemand > 2500) {
    recommendations.add(
      PlanningRecommendation(
        title: 'High Demand Alert',
        description:
            'Predicted demand is ${prediction.predictedDemand.toStringAsFixed(0)} units, which is above optimal levels. Consider bulk ordering to reduce per-unit costs and improve supply chain efficiency.',
        icon: Icons.trending_up,
        color: Colors.orange,
        priority: 'High',
        category: 'Demand Management',
      ),
    );
  } else if (prediction.predictedDemand < 1000) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Low Demand Opportunity',
        description:
            'Predicted demand is ${prediction.predictedDemand.toStringAsFixed(0)} units. This is a good time to optimize inventory and reduce excess stock. Consider consolidating orders with other regions.',
        icon: Icons.trending_down,
        color: Colors.blue,
        priority: 'Medium',
        category: 'Inventory Optimization',
      ),
    );
  }

  final carbonPerUnit =
      prediction.carbonFootprint / prediction.predictedDemand;
  if (carbonPerUnit > 2.5) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Carbon Footprint Reduction',
        description:
            'Carbon footprint per unit is ${carbonPerUnit.toStringAsFixed(2)} kg CO₂, which is above optimal. Consider sourcing from local suppliers or using eco-friendly transportation methods to reduce emissions.',
        icon: Icons.eco,
        color: Colors.green,
        priority: 'High',
        category: 'Sustainability',
      ),
    );
  } else if (carbonPerUnit < 2.0) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Excellent Carbon Efficiency',
        description:
            'Your carbon footprint per unit is ${carbonPerUnit.toStringAsFixed(2)} kg CO₂, which is below average. Maintain this sustainable approach and consider sharing best practices with other regions.',
        icon: Icons.verified,
        color: Colors.green,
        priority: 'Low',
        category: 'Sustainability',
      ),
    );
  }

  if (prediction.sustainabilityScore < 70) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Improve Sustainability Score',
        description:
            'Current sustainability score is ${prediction.sustainabilityScore.toStringAsFixed(0)}/100. Focus on reducing waste, optimizing demand forecasting, and improving supply chain efficiency to boost your ESG rating.',
        icon: Icons.star_border,
        color: Colors.amber,
        priority: 'High',
        category: 'ESG Performance',
      ),
    );
  }

  if (weather.temperature > 40) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Extreme Heat Warning',
        description:
            'Temperature is ${weather.temperature.toStringAsFixed(1)}°C. High temperatures accelerate V-belt degradation. Consider ordering belts with higher temperature resistance or increasing inventory buffer by 15-20%.',
        icon: Icons.warning,
        color: Colors.red,
        priority: 'High',
        category: 'Weather Impact',
      ),
    );
  } else if (weather.humidity > 75) {
    recommendations.add(
      PlanningRecommendation(
        title: 'High Humidity Alert',
        description:
            'Humidity is ${weather.humidity.toStringAsFixed(0)}%. High humidity can cause belt deterioration. Ensure proper storage conditions and consider moisture-resistant belt options.',
        icon: Icons.water_drop,
        color: Colors.cyan,
        priority: 'Medium',
        category: 'Weather Impact',
      ),
    );
  }

  if (prediction.wasteReductionScore < 70) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Optimize Waste Reduction',
        description:
            'Waste reduction score is ${prediction.wasteReductionScore.toStringAsFixed(0)}/100. Implement just-in-time inventory management and improve demand forecasting accuracy to reduce waste and improve sustainability.',
        icon: Icons.recycling,
        color: Colors.teal,
        priority: 'Medium',
        category: 'Waste Management',
      ),
    );
  }

  if (prediction.profitScore < 60) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Profit Optimization Opportunity',
        description:
            'Profit score is ${prediction.profitScore.toStringAsFixed(0)}/100. Consider negotiating bulk discounts, optimizing supplier relationships, or adjusting pricing strategy for this region and season.',
        icon: Icons.attach_money,
        color: Colors.blue,
        priority: 'Medium',
        category: 'Financial',
      ),
    );
  }

  if (prediction.orderAccuracyScore < 80) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Improve Order Accuracy',
        description:
            'Order accuracy score is ${prediction.orderAccuracyScore.toStringAsFixed(0)}/100. Enhance demand forecasting models and consider historical data analysis to improve prediction confidence.',
        icon: Icons.analytics,
        color: Colors.purple,
        priority: 'Medium',
        category: 'Forecasting',
      ),
    );
  }

  if (season == 'Summer' && prediction.predictedDemand > 2000) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Summer Peak Season Strategy',
        description:
            'Summer typically sees increased demand. Plan ahead by securing supplier commitments early, building inventory buffers, and implementing flexible delivery schedules to meet peak demand.',
        icon: Icons.wb_sunny,
        color: Colors.orange,
        priority: 'High',
        category: 'Seasonal Planning',
      ),
    );
  } else if (season == 'Winter' && prediction.predictedDemand < 1500) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Winter Inventory Management',
        description:
            'Winter shows lower demand. Use this period to optimize inventory, conduct maintenance, and negotiate better terms with suppliers for the upcoming high-demand seasons.',
        icon: Icons.ac_unit,
        color: Colors.blue,
        priority: 'Low',
        category: 'Seasonal Planning',
      ),
    );
  }

  if (region == 'Dubai' && weather.temperature > 35) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Dubai Heat Management',
        description:
            'Dubai\'s extreme heat requires special attention. Consider heat-resistant V-belt specifications, shorter replacement cycles, and climate-controlled storage facilities.',
        icon: Icons.location_on,
        color: Colors.orange,
        priority: 'High',
        category: 'Regional Strategy',
      ),
    );
  } else if (region == 'India' && season == 'Summer') {
    recommendations.add(
      PlanningRecommendation(
        title: 'India Monsoon Preparation',
        description:
            'Prepare for monsoon season in India. High humidity and rainfall can impact belt performance. Stock moisture-resistant variants and plan for potential supply chain disruptions.',
        icon: Icons.cloud,
        color: Colors.cyan,
        priority: 'High',
        category: 'Regional Strategy',
      ),
    );
  }

  if (prediction.sustainabilityScore > 80 &&
      prediction.profitScore > 70 &&
      prediction.wasteReductionScore > 75) {
    recommendations.add(
      PlanningRecommendation(
        title: 'Excellent Performance',
        description:
            'Your current metrics show excellent performance across sustainability, profit, and waste reduction. Maintain these practices and consider scaling successful strategies to other regions.',
        icon: Icons.celebration,
        color: Colors.green,
        priority: 'Low',
        category: 'Best Practices',
      ),
    );
  }

  return recommendations;
}
