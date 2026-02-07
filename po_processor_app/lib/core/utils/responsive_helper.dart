import 'package:flutter/material.dart';

/// Responsive helper utility for adaptive UI design
class ResponsiveHelper {
  /// Get screen width
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Get screen height
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// Check if device is mobile (width < 600)
  static bool isMobile(BuildContext context) {
    return screenWidth(context) < 600;
  }

  /// Check if device is tablet (600 <= width < 1024)
  static bool isTablet(BuildContext context) {
    final width = screenWidth(context);
    return width >= 600 && width < 1024;
  }

  /// Check if device is desktop (width >= 1024)
  static bool isDesktop(BuildContext context) {
    return screenWidth(context) >= 1024;
  }

  /// Get responsive padding based on screen size
  static EdgeInsets responsivePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(12.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(16.0);
    } else {
      return const EdgeInsets.all(20.0);
    }
  }

  /// Get responsive horizontal padding
  static EdgeInsets responsiveHorizontalPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: 12.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 16.0);
    } else {
      return const EdgeInsets.symmetric(horizontal: 20.0);
    }
  }

  /// Get responsive vertical padding
  static EdgeInsets responsiveVerticalPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(vertical: 12.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(vertical: 16.0);
    } else {
      return const EdgeInsets.symmetric(vertical: 20.0);
    }
  }

  /// Get responsive spacing between elements
  static double responsiveSpacing(BuildContext context) {
    if (isMobile(context)) {
      return 12.0;
    } else if (isTablet(context)) {
      return 16.0;
    } else {
      return 24.0;
    }
  }

  /// Get responsive font size multiplier
  static double responsiveFontSize(BuildContext context, double baseSize) {
    if (isMobile(context)) {
      return baseSize * 0.9;
    } else if (isTablet(context)) {
      return baseSize;
    } else {
      return baseSize * 1.1;
    }
  }

  /// Get responsive card padding
  static EdgeInsets responsiveCardPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(12.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(16.0);
    } else {
      return const EdgeInsets.all(20.0);
    }
  }

  /// Get responsive button padding
  static EdgeInsets responsiveButtonPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(vertical: 16.0, horizontal: 18.0);
    } else {
      return const EdgeInsets.symmetric(vertical: 18.0, horizontal: 20.0);
    }
  }

  /// Get responsive icon size
  static double responsiveIconSize(BuildContext context, double baseSize) {
    if (isMobile(context)) {
      return baseSize * 0.85;
    } else if (isTablet(context)) {
      return baseSize;
    } else {
      return baseSize * 1.1;
    }
  }

  /// Get responsive width for stat cards
  static double responsiveStatCardWidth(BuildContext context) {
    if (isMobile(context)) {
      return screenWidth(context) * 0.75; // 75% of screen width on mobile
    } else if (isTablet(context)) {
      return 200.0;
    } else {
      return 220.0;
    }
  }

  /// Get number of columns for grid layout
  static int responsiveGridColumns(BuildContext context) {
    if (isMobile(context)) {
      return 1;
    } else if (isTablet(context)) {
      return 2;
    } else {
      return 4;
    }
  }

  /// Get responsive border radius
  static double responsiveBorderRadius(BuildContext context) {
    if (isMobile(context)) {
      return 12.0;
    } else if (isTablet(context)) {
      return 16.0;
    } else {
      return 20.0;
    }
  }

  /// Get responsive chart height
  static double responsiveChartHeight(BuildContext context) {
    if (isMobile(context)) {
      return 200.0;
    } else if (isTablet(context)) {
      return 250.0;
    } else {
      return 300.0;
    }
  }
}

