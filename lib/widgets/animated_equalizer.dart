// widgets/animated_equalizer.dart
// Animated bouncing bars equalizer icon for currently playing songs.
import 'package:flutter/material.dart';

class AnimatedEqualizer extends StatefulWidget {
  final Color color;
  final double size;
  const AnimatedEqualizer({
    super.key,
    this.color = const Color(0xFF1DB954),
    this.size = 18,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  static const _barCount = 3;
  // Different durations for organic feel
  static const _durations = [450, 550, 400];
  // Different min/max heights for variety
  static const _minFactors = [0.25, 0.2, 0.3];
  static const _maxFactors = [1.0, 0.85, 0.95];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_barCount, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _durations[i]),
      );
    });

    _animations = List.generate(_barCount, (i) {
      final anim = Tween<double>(
        begin: _minFactors[i],
        end: _maxFactors[i],
      ).animate(CurvedAnimation(
        parent: _controllers[i],
        curve: Curves.easeInOut,
      ));
      // Start with staggered delays
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
      return anim;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / 5;
    final gap = widget.size / 10;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_barCount, (i) {
            return AnimatedBuilder(
              animation: _animations[i],
              builder: (_, __) {
                return Container(
                  width: barWidth,
                  height: widget.size * _animations[i].value,
                  margin: EdgeInsets.only(right: i < _barCount - 1 ? gap : 0),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(barWidth / 2),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
