import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Weather Service using OpenWeatherMap API
/// API Key: ce4410d3c07a35dc0010052ed4f67255
class WeatherService {
  static const String _apiKey = 'ce4410d3c07a35dc0010052ed4f67255';
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  /// Get weather data for a region
  static Future<WeatherData> getWeatherData(String region) async {
    final coordinates = _getRegionCoordinates(region);
    
    try {
      final url = Uri.parse(
        '$_baseUrl/weather?lat=${coordinates['lat']}&lon=${coordinates['lon']}&appid=$_apiKey&units=metric',
      );
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return WeatherData.fromJson(data);
      } else {
        throw Exception('Weather API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching weather: $e');
      // Return default weather data on error
      return WeatherData(
        temperature: _getDefaultTemperature(region),
        humidity: 60.0,
        condition: 'Clear',
        windSpeed: 10.0,
      );
    }
  }

  /// Get forecast for a specific month
  static Future<List<WeatherData>> getMonthlyForecast(
    String region,
    int month,
  ) async {
    // For simplicity, generate forecast based on region and month
    // In production, use OpenWeatherMap forecast API
    final baseWeather = await getWeatherData(region);
    final List<WeatherData> forecast = [];

    for (int day = 1; day <= 30; day++) {
      forecast.add(WeatherData(
        temperature: baseWeather.temperature +
            (day % 7 - 3) * 2, // Simulate daily variation
        humidity: baseWeather.humidity + (day % 5 - 2) * 5,
        condition: baseWeather.condition,
        windSpeed: baseWeather.windSpeed + (day % 3 - 1) * 2,
      ));
    }

    return forecast;
  }

  static Map<String, double> _getRegionCoordinates(String region) {
    switch (region) {
      case 'Dubai':
        return {'lat': 25.2048, 'lon': 55.2708};
      case 'Germany':
        return {'lat': 52.5200, 'lon': 13.4050}; // Berlin
      case 'India':
        return {'lat': 28.6139, 'lon': 77.2090}; // New Delhi
      default:
        return {'lat': 25.2048, 'lon': 55.2708}; // Default to Dubai
    }
  }

  static double _getDefaultTemperature(String region) {
    switch (region) {
      case 'Dubai':
        return 35.0; // Hot
      case 'Germany':
        return 15.0; // Moderate
      case 'India':
        return 28.0; // Warm
      default:
        return 25.0;
    }
  }
}

class WeatherData {
  final double temperature;
  final double humidity;
  final String condition;
  final double windSpeed;

  WeatherData({
    required this.temperature,
    required this.humidity,
    required this.condition,
    required this.windSpeed,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['main']?['temp'] ?? 25.0).toDouble(),
      humidity: (json['main']?['humidity'] ?? 60.0).toDouble(),
      condition: json['weather']?[0]?['main'] ?? 'Clear',
      windSpeed: (json['wind']?['speed'] ?? 10.0).toDouble(),
    );
  }

  /// Calculate weather degradation factor for V-belts
  double get degradationFactor {
    double factor = 1.0;

    // High temperature increases degradation
    if (temperature > 40) {
      factor += (temperature - 40) * 0.02; // 2% per degree above 40°C
    }

    // High humidity increases degradation
    if (humidity > 70) {
      factor += (humidity - 70) * 0.01; // 1% per % above 70%
    }

    // Extreme conditions
    if (condition == 'Rain' || condition == 'Storm') {
      factor += 0.1;
    }

    return factor.clamp(1.0, 2.0);
  }
}

