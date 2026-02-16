import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Progress bar with color #181717 and animated pulse effect.
class PulseProgressBar extends StatefulWidget {
  final double? value;
  final Color? backgroundColor;

  const PulseProgressBar({
    super.key,
    this.value,
    this.backgroundColor,
  });

  @override
  State<PulseProgressBar> createState() => _PulseProgressBarState();
}

class _PulseProgressBarState extends State<PulseProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _pulseAnimation.value,
          child: child,
        );
      },
      child: LinearProgressIndicator(
        value: widget.value,
        backgroundColor: widget.backgroundColor ?? Colors.white24,
        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.brandCharcoal),
      ),
    );
  }
}
