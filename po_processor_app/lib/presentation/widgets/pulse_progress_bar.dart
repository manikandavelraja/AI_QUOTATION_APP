import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Progress bar with color #181717 and animated pulse + shimmer effect
/// to indicate active background processing.
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
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? Colors.white24;
    final barColor = AppTheme.iconGraphGreen;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _shimmerAnimation]),
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                // Background
                Container(
                  width: double.infinity,
                  height: 8,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Filled progress with pulse opacity
                FractionallySizedBox(
                  widthFactor: widget.value?.clamp(0.0, 1.0) ?? 0.0,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: barColor.withOpacity(_pulseAnimation.value),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // Shimmer overlay (sliding highlight)
                if (widget.value != null && widget.value! > 0 && widget.value! < 1)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final shimmerWidth = constraints.maxWidth * 0.35;
                        final left = _shimmerAnimation.value * (constraints.maxWidth + shimmerWidth) - shimmerWidth;
                        return OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: 0,
                          maxWidth: constraints.maxWidth + shimmerWidth,
                          child: Transform.translate(
                            offset: Offset(left, 0),
                            child: Container(
                              width: shimmerWidth,
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withOpacity(0.45),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A widget that sizes its child to a fraction of the parent's width.
class FractionallySizedBox extends StatelessWidget {
  final double widthFactor;
  final Widget child;

  const FractionallySizedBox({
    super.key,
    required this.widthFactor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * widthFactor.clamp(0.0, 1.0);
        return SizedBox(
          width: width,
          child: child,
        );
      },
    );
  }
}
