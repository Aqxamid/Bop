import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import '../../theme/app_theme.dart';
import '../../models/wrapped_report.dart';
import '../../services/db_service.dart';
import '../../services/llm_service.dart';
import '../../models/song.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/settings_provider.dart';
import '../../models/playlist.dart';
import '../../widgets/animated_equalizer.dart';
import '../../providers/player_provider.dart';
import '../../widgets/playlist_collage.dart';
import '../../widgets/wrapped_receipt_widget.dart';
import '../../services/share_service.dart';

IconData _personalityIcon(String iconName) {
  switch (iconName) {
    case 'nightlife':    return Icons.nightlife;
    case 'wb_twilight':  return Icons.wb_twilight;
    case 'fast_forward': return Icons.fast_forward;
    case 'headphones':   return Icons.headphones;
    case 'music_note':   return Icons.music_note;
    default:             return Icons.music_note;
  }
}

enum _AnimType { blobs, particles, waves, liquid, nebula, aurora }

class RecapTheme {
  final LinearGradient gradient;
  final Color shapeColor;
  final _AnimType yearlyType;

  RecapTheme({required this.gradient, required this.shapeColor, required this.yearlyType});

  static RecapTheme get(int month, bool isYearly) {
    if (isYearly) {
      return RecapTheme(
        gradient: const LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFF191414)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        shapeColor: Colors.amber,
        yearlyType: _AnimType.nebula,
      );
    }

    switch (month) {
      case 1:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFF85D8CE), Color(0xFF085078)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.white70,
          yearlyType: _AnimType.particles,
        );
      case 2:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFFF06292), Color(0xFF880E4F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.pinkAccent,
          yearlyType: _AnimType.liquid,
        );
      case 3:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFF66BB6A), Color(0xFF1B5E20)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.lightGreenAccent,
          yearlyType: _AnimType.waves,
        );
      case 4:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFF9575CD), Color(0xFF311B92)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.deepPurpleAccent,
          yearlyType: _AnimType.particles,
        );
      case 5:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFF57F17)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.yellowAccent,
          yearlyType: _AnimType.blobs,
        );
      case 6:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFF4DB6AC), Color(0xFF004D40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.cyanAccent,
          yearlyType: _AnimType.waves,
        );
      case 7:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFFFF8A65), Color(0xFFBF360C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.deepOrangeAccent,
          yearlyType: _AnimType.liquid,
        );
      case 8:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFFFFB74D), Color(0xFFE65100)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.orangeAccent,
          yearlyType: _AnimType.aurora,
        );
      case 9:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFFA1887F), Color(0xFF3E2723)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.brown,
          yearlyType: _AnimType.particles,
        );
      case 10:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFFBA68C8), Color(0xFF4A148C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.orange,
          yearlyType: _AnimType.nebula,
        );
      case 11:
        return RecapTheme(
          gradient: const LinearGradient(colors: [Color(0xFF90A4AE), Color(0xFF263238)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.blueGrey,
          yearlyType: _AnimType.aurora,
        );
      case 12:
      default:
        return RecapTheme(
          gradient: const LinearGradient(colors: [BopTheme.green, Color(0xFF1B5E20)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shapeColor: Colors.amber,
          yearlyType: _AnimType.aurora,
        );
    }
  }
}

class WrappedSlideshowScreen extends ConsumerStatefulWidget {
  final WrappedReport report;
  const WrappedSlideshowScreen({super.key, required this.report});

  @override
  ConsumerState<WrappedSlideshowScreen> createState() => _WrappedSlideshowScreenState();
}

class _WrappedSlideshowScreenState extends ConsumerState<WrappedSlideshowScreen> with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  // Standardize on false for the bold rendition cleanup
  int get _totalPages => _buildSlides(false).length;
  late AnimationController _progressController;
  bool _isPaused = false;
  final AudioPlayer _snippetPlayer = AudioPlayer();
  final ScreenshotController _screenshotController = ScreenshotController();

  WrappedReport get r => widget.report;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });
    _progressController.forward();
    // We now ensure generation is done BEFORE pushing to this screen in stats_screen.dart
    // but we keep this as a lightweight fallback just in case.
    if (r.llmRecap.isEmpty) {
      _triggerLlmGeneration();
    }
    _preloadTop5();
  }

  List<Song> _top5Songs = [];
  void _preloadTop5() async {
    try {
      final data = jsonDecode(r.slidesJsonStr);
      if (data != null && data['topSongs'] != null) {
        final top5Data = data['topSongs'] as List<dynamic>;
        final List<Song> loaded = [];
        for (final item in top5Data.take(5)) {
          final id = item['id'] as int?;
          if (id != null) {
            final s = await DbService.instance.isar.songs.get(id);
            if (s != null) loaded.add(s);
          }
        }
        if (mounted) setState(() => _top5Songs = loaded);
      }
    } catch (_) {}
  }

  Future<void> _triggerLlmGeneration() async {
    if (r.llmRecap.isEmpty) {
      final recap = await LlmService.instance.generateWrappedRecap(r);
      if (mounted) {
        setState(() {
          r.llmRecap = recap;
        });
      }
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pageController.dispose();
    _snippetPlayer.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _progressController.stop();
        _snippetPlayer.pause();
      } else {
        _progressController.forward();
        if (_snippetPlayer.processingState != ProcessingState.idle) {
          _snippetPlayer.play();
        }
      }
    });
  }

  void _handlePageChange(int i) {
    setState(() {
      _currentPage = i;
      _isPaused = false; // Reset pause on page change
    });
    
    if (i == _totalPages - 1) {
      _progressController.stop();
      _progressController.value = 1.0;
    } else {
      _progressController.forward(from: 0.0);
    }

    final slides = _buildSlides(false);
    if (i < slides.length && slides[i] is _TopSongCard) {
      _playSnippet();
    } else {
      _snippetPlayer.stop();
    }
  }

  Future<void> _playSnippet() async {
    try {
      final songs = await DbService.instance.songs.filter().titleEqualTo(r.topSong).findAll();
      if (songs.isNotEmpty) {
        final song = songs.first;
        await _snippetPlayer.setFilePath(song.filePath);
        final dur = _snippetPlayer.duration?.inMilliseconds ?? 0;
        if (dur > 60000) {
          await _snippetPlayer.seek(const Duration(minutes: 1));
        } else {
          await _snippetPlayer.seek(Duration(milliseconds: (dur * 0.3).toInt()));
        }
        if (!_isPaused) _snippetPlayer.play();
      }
    } catch (_) {}
  }

  List<Widget> _buildSlides(bool isBold) {
    final hasMinutes = r.totalMinutes > 0;
    final hasSongs = r.topSong.isNotEmpty || (r.slidesJsonStr.isNotEmpty && r.slidesJsonStr != '[]');
    final hasGenres = r.genreJsonStr.isNotEmpty && r.genreJsonStr != '{}';
    final hasPersonality = r.personalityType != 'The Mystery' && r.personalityType != 'Unknown';

    return [
      _IntroCard(report: r, isBold: isBold),
      _MinutesCard(report: r, isBold: isBold),
      if (hasMinutes) ...[
        _TopArtistCard(report: r, isBold: isBold),
        if (hasSongs) ...[
          _TopSongCard(report: r, isBold: isBold),
          _Top5Card(report: r, isBold: isBold, loadedSongs: _top5Songs),
        ],
        _VibeMapCard(report: r, isBold: isBold),
        _TimeInsightCard(report: r, isBold: isBold),
        if (hasPersonality) _PersonalityInsightCard(report: r, isBold: isBold),
        if (hasMinutes) _LLMRecapCard(report: r, isBold: isBold),
      ],
      _ShareCard(report: r, isBold: isBold),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer(
        builder: (context, ref, child) {
          // Force standard design
          const isBold = false;
          final slides = _buildSlides(isBold);
          return GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity! > 500) {
                Navigator.pop(context);
              }
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity! < -500) {
                _next();
              } else if (details.primaryVelocity! > 500) {
                if (_currentPage > 0) {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              }
            },
            onTapUp: (d) {
              final half = MediaQuery.of(context).size.width / 2;
              if (d.globalPosition.dx > half) {
                _next();
              } else if (_currentPage > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
            child: Stack(
              children: [
                PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: _handlePageChange,
                  children: slides,
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: List.generate(
                      _totalPages,
                      (i) => Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: i < _currentPage
                              ? Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))
                              : i == _currentPage
                                  ? FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _progressController.value,
                                      child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 24,
                  right: 8,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white70),
                        onPressed: _togglePause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Slide base widget ─────────────────────────────────────────
class _Slide extends StatelessWidget {
  final Widget child;
  final LinearGradient gradient;
  final bool isBold;

  const _Slide({required this.child, required this.gradient, required this.isBold});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(gradient: gradient),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.04)),
            ),
          ),
          if (isBold)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GeometricPainter(
                    Colors.white.withOpacity(0.08),
                    seed: gradient.hashCode,
                    isBold: true,
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                height: MediaQuery.of(context).size.height * 0.72,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -15,
                        top: -15,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.04)),
                        ),
                      ),
                      Positioned.fill(child: CustomPaint(painter: _GeometricPainter(Colors.white.withOpacity(0.03), seed: gradient.hashCode + 1, isBold: false))),
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbstractAnimation extends StatefulWidget {
  final Widget child;
  final Color shapeColor;
  final _AnimType type;
  final bool isBold;
  const _AbstractAnimation({required this.child, required this.shapeColor, this.type = _AnimType.blobs, required this.isBold});

  @override
  State<_AbstractAnimation> createState() => _AbstractAnimationState();
}

class _AbstractAnimationState extends State<_AbstractAnimation> with TickerProviderStateMixin {
  late AnimationController _mainAnim;
  late List<Offset> _points;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _mainAnim = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();
    _points = List.generate(20, (index) => Offset(_rng.nextDouble(), _rng.nextDouble()));
  }

  @override
  void dispose() {
    _mainAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildBackground(),
        widget.child,
      ],
    );
  }

  Widget _buildBackground() {
    Widget child;
    switch (widget.type) {
      case _AnimType.waves:
        child = AnimatedBuilder(
          animation: _mainAnim,
          builder: (context, _) => CustomPaint(
            painter: _WavePainter(_mainAnim.value, widget.shapeColor),
            size: Size.infinite,
          ),
        );
        break;
      case _AnimType.liquid:
        child = AnimatedBuilder(
          animation: _mainAnim,
          builder: (context, _) => CustomPaint(
            painter: _LiquidPainter(_mainAnim.value, widget.shapeColor),
            size: Size.infinite,
          ),
        );
        break;
      case _AnimType.nebula:
        child = AnimatedBuilder(
          animation: _mainAnim,
          builder: (context, _) => CustomPaint(
            painter: _NebulaPainter(_mainAnim.value, widget.shapeColor),
            size: Size.infinite,
          ),
        );
        break;
      case _AnimType.aurora:
        child = AnimatedBuilder(
          animation: _mainAnim,
          builder: (context, _) => CustomPaint(
            painter: _AuroraPainter(_mainAnim.value, widget.shapeColor),
            size: Size.infinite,
          ),
        );
        break;
      case _AnimType.particles:
        child = CustomPaint(
          painter: _GeometricPainter(widget.shapeColor, seed: 99, isBold: false),
          size: Size.infinite,
        );
        break;
      case _AnimType.blobs:
      default:
        child = AnimatedBuilder(
          animation: _mainAnim,
          builder: (_, __) {
            return Stack(
              children: [
                Positioned(
                  top: -50 + sin(_mainAnim.value * 2 * pi) * 100,
                  right: -100 + cos(_mainAnim.value * 2 * pi) * 50,
                  child: Opacity(
                    opacity: 0.15,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.shapeColor,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -100 + cos(_mainAnim.value * 2 * pi) * 80,
                  left: -50 + sin(_mainAnim.value * 2 * pi) * 40,
                  child: Opacity(
                    opacity: 0.1,
                    child: Container(
                      width: 350,
                      height: 350,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.shapeColor.withBlue(200),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
    }
    return RepaintBoundary(child: child);
  }
}

class _ParticlePainter extends CustomPainter {
  final List<Offset> points;
  final double animation;
  final Color color;
  _ParticlePainter(this.points, this.animation, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.2);
    for (var p in points) {
      final x = (p.dx * size.width + sin(animation * 2 * pi + p.dx * 10) * 20) % size.width;
      final y = (p.dy * size.height + cos(animation * 2 * pi + p.dy * 10) * 20) % size.height;
      canvas.drawCircle(Offset(x, y), 2 + p.dx * 5, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

class _WavePainter extends CustomPainter {
  final double animation;
  final Color color;
  _WavePainter(this.animation, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.12)..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, size.height * 0.7);
    for (double i = 0; i <= size.width; i++) {
      path.lineTo(i, size.height * 0.7 + sin((i / size.width * 2 * pi) + (animation * 2 * pi)) * 30);
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);

    final path2 = Path();
    path2.moveTo(0, size.height * 0.8);
    for (double i = 0; i <= size.width; i++) {
      path2.lineTo(i, size.height * 0.8 + cos((i / size.width * 2 * pi) + (animation * 4 * pi)) * 20);
    }
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

class _StarBlobPainter extends CustomPainter {
  final Color color;
  final double animation;
  _StarBlobPainter(this.color, this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.45;
    final path = Path();

    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final isInner = i % 2 == 1;
      final angle = (i * pi / points) + (animation * 0.5);
      final r = isInner ? radius * 0.75 : radius;
      final x = center.dx + cos(angle) * r;
      final y = center.dy + sin(angle) * r;
      if (i == 0) path.moveTo(x, y);
      else path.quadraticBezierTo(
        center.dx + cos(angle - pi/points/2) * (isInner ? radius * 0.9 : radius * 0.8),
        center.dy + sin(angle - pi/points/2) * (isInner ? radius * 0.9 : radius * 0.8),
        x, y,
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _LiquidPainter extends CustomPainter {
  final double animation;
  final Color color;
  _LiquidPainter(this.animation, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.1);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;

    final path = Path();
    for (double i = 0; i <= 2 * pi; i += 0.1) {
      final r = radius + sin(i * 5 + animation * 2 * pi) * 20;
      final x = center.dx + r * cos(i);
      final y = center.dy + r * sin(i);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiquidPainter old) => true;
}

class _NebulaPainter extends CustomPainter {
  final double animation;
  final Color color;
  _NebulaPainter(this.animation, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    for (int i = 0; i < 3; i++) {
      final r = size.width * (0.6 + i * 0.1);
      final x = size.width * 0.5 + sin(animation * 2 * pi + i) * 50;
      final y = size.height * 0.5 + cos(animation * 2 * pi + i) * 50;
      paint.color = color.withOpacity(0.15 - i * 0.03);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _AuroraPainter extends CustomPainter {
  final double animation;
  final Color color;
  _AuroraPainter(this.animation, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    final path = Path();
    for (int i = 0; i < 2; i++) {
      path.reset();
      final yBase = size.height * (0.3 + i * 0.2);
      path.moveTo(0, yBase);
      for (double x = 0; x <= size.width; x += 10) {
        final y = yBase + sin(x / 50 + animation * 4 * pi + i) * 40;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      paint.color = color.withOpacity(0.1 + i * 0.05);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GeometricPainter extends CustomPainter {
  final Color color;
  final int seed;
  final bool isBold;
  _GeometricPainter(this.color, {this.seed = 42, this.isBold = false});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final count = isBold ? 15 : 12;

    for (int i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final sizeVal = (isBold ? 80.0 : 60.0) + random.nextDouble() * 140.0;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(random.nextDouble() * 2 * pi);

      final shapePaint = Paint()
        ..color = color.withOpacity(isBold ? (0.05 + random.nextDouble() * 0.08) : 0.05)
        ..style = PaintingStyle.fill;

      final type = random.nextInt(6);
      if (type == 0) {
        final p = Path();
        for (int j = 0; j < 4; j++) {
          final angle = j * pi / 2;
          final r1 = sizeVal / 2;
          if (j == 0) p.moveTo(r1 * cos(angle), r1 * sin(angle));
          else p.lineTo(r1 * cos(angle), r1 * sin(angle));
          p.quadraticBezierTo(0, 0, r1 * cos(angle + pi/2), r1 * sin(angle + pi/2));
        }
        canvas.drawPath(p, shapePaint);
      } else if (type == 1) {
        for (int j = 0; j < 4; j++) {
          canvas.save();
          canvas.rotate(j * pi / 2);
          canvas.drawCircle(Offset(sizeVal / 4, 0), sizeVal / 4, shapePaint);
          canvas.restore();
        }
      } else if (type == 2) {
        final p = Path();
        const pts = 12;
        for (int j = 0; j < pts * 2; j++) {
          final r = j.isEven ? sizeVal / 2 : sizeVal / 4;
          final angle = j * pi / pts;
          if (j == 0) p.moveTo(r * cos(angle), r * sin(angle));
          else p.lineTo(r * cos(angle), r * sin(angle));
        }
        p.close();
        canvas.drawPath(p, shapePaint);
      } else if (type == 3) {
        final s = sizeVal / 2;
        final p = Path()
          ..moveTo(0, -s)
          ..lineTo(s, 0)
          ..lineTo(0, s)
          ..lineTo(-s, 0)
          ..close();
        canvas.drawPath(p, shapePaint);
      } else if (type == 4) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-sizeVal/2, -sizeVal/2, sizeVal, sizeVal), Radius.circular(sizeVal/4)), shapePaint);
      } else {
        canvas.drawCircle(Offset.zero, sizeVal / 2, shapePaint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GeometricPainter oldDelegate) => oldDelegate.seed != seed || oldDelegate.color != color;
}

class _BoldSlide extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;
  final Widget child;

  const _BoldSlide({
    required this.backgroundColor,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GeometricPainter(accentColor, isBold: true, seed: backgroundColor.hashCode),
            ),
          ),
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 40, offset: const Offset(0, 20))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: _GeometricPainter(backgroundColor.withOpacity(0.1), seed: backgroundColor.hashCode + 2, isBold: true))),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: child,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card 1: Intro ─────────────────────────────────────────────
class _IntroCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _IntroCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');
    final monthName = report.cadence == 'yearly' ? '' : months[report.generatedAt.month - 1];

    return _Slide(
      gradient: theme.gradient,
      isBold: isBold,
      child: _AbstractAnimation(
        shapeColor: theme.shapeColor,
        type: report.cadence == 'yearly' ? _AnimType.nebula : theme.yearlyType,
        isBold: isBold,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$monthName ${report.generatedAt.year}'.trim(),
                  style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text(report.cadence == 'yearly' ? 'Your\nYear\nin Music' : 'Your\nMonth\nin Music',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                      letterSpacing: -2)),
              const SizedBox(height: 32),
              const Text('Tap to see your story',
                  style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card 2: Minutes ───────────────────────────────────────────
class _MinutesCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _MinutesCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');
    final hrs = report.totalMinutes ~/ 60;

    return _Slide(
      gradient: theme.gradient,
      isBold: isBold,
      child: _AbstractAnimation(
        shapeColor: theme.shapeColor,
        type: report.cadence == 'yearly' ? _AnimType.aurora : _AnimType.particles,
        isBold: isBold,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('minutes listened',
                  style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
              const SizedBox(height: 16),
              Text('${report.totalMinutes}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 92,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -3)),
              const SizedBox(height: 24),
              Builder(builder: (context) {
                String insight = "That's $hrs hours.\nWe're not judging.\nOkay we're a little judging.";
                try {
                  final data = jsonDecode(report.slidesJsonStr);
                  if (data['insights'] != null && data['insights']['minutesInsight'] != null) {
                    insight = data['insights']['minutesInsight'].replaceAll('\\n', '\n');
                  }
                } catch (_) {}
                return Text(
                  insight,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.4, fontWeight: FontWeight.w500),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card 3: Top Artist ────────────────────────────────────────
class _TopArtistCard extends StatefulWidget {
  final WrappedReport report;
  final bool isBold;
  const _TopArtistCard({required this.report, required this.isBold});

  @override
  State<_TopArtistCard> createState() => _TopArtistCardState();
}

class _TopArtistCardState extends State<_TopArtistCard> {
  Uint8List? _artistArt;

  @override
  void initState() {
    super.initState();
    _loadArtistArt();
  }

  Future<void> _loadArtistArt() async {
    final allSongs = await DbService.instance.songs.where().findAll();
    final songs = allSongs.where((s) => s.artist == widget.report.topArtist).toList();
    for (final song in songs) {
      if (song.artBytes != null && song.artBytes!.isNotEmpty) {
        if (mounted) setState(() => _artistArt = Uint8List.fromList(song.artBytes!));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(widget.report.generatedAt.month, widget.report.cadence == 'yearly');
    return _Slide(
      gradient: theme.gradient,
      isBold: widget.isBold,
      child: Stack(
        children: [
          _AbstractAnimation(
            shapeColor: theme.shapeColor,
            type: _AnimType.liquid,
            isBold: widget.isBold,
            child: const SizedBox.expand(),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('your top artist',
                    style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
                const SizedBox(height: 32),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(300, 300),
                      painter: _StarBlobPainter(theme.shapeColor, 0),
                    ),
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC0392B),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                        ],
                      ),
                      child: ClipOval(
                        child: _artistArt != null
                            ? Image.memory(_artistArt!, fit: BoxFit.cover, width: 140, height: 140, cacheWidth: 280, cacheHeight: 280)
                            : Center(
                                child: Text(
                                  widget.report.topArtist.isNotEmpty ? widget.report.topArtist[0].toUpperCase() : '♪',
                                  style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(widget.report.topArtist,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                const SizedBox(height: 8),
                Text('${widget.report.topArtistPlays} plays',
                    style: const TextStyle(color: BopTheme.green, fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 24),
                Builder(builder: (context) {
                  String insight = "They were there for you.\nSuspiciously often.";
                  try {
                    final data = jsonDecode(widget.report.slidesJsonStr);
                    if (data['insights'] != null && data['insights']['artistInsight'] != null) {
                      insight = data['insights']['artistInsight'].replaceAll('\\n', '\n');
                    }
                  } catch (_) {}
                  return Text(
                    insight,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card 4: Top Song ──────────────────────────────────────────
class _TopSongCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _TopSongCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');
    return _Slide(
      gradient: theme.gradient,
      isBold: isBold,
      child: _AbstractAnimation(
        shapeColor: theme.shapeColor,
        type: _AnimType.liquid,
        isBold: isBold,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: const AlwaysStoppedAnimation(0),
                builder: (context, _) => CustomPaint(
                  painter: _WavePainter(0.2, theme.shapeColor),
                  size: Size.infinite,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('the song that defined it',
                      style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
                  const SizedBox(height: 32),
                  const Icon(Icons.music_note, color: Colors.white, size: 82),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(report.topSong,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -1.5)),
                  ),
                  const SizedBox(height: 32),
                  Builder(builder: (context) {
                    String insight = "Turn it up.\nThis one is yours.";
                    try {
                      final data = jsonDecode(report.slidesJsonStr);
                      if (data['insights'] != null && data['insights']['songInsight'] != null) {
                        insight = data['insights']['songInsight'].replaceAll('\\n', '\n');
                      }
                    } catch (_) {}
                    return Text(
                      insight,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.4, fontWeight: FontWeight.w500),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card 5: Top 5 Songs ───────────────────────────────────────
class _Top5Card extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  final List<Song> loadedSongs;
  const _Top5Card({required this.report, required this.isBold, required this.loadedSongs});

  @override
  Widget build(BuildContext context) {
    List<dynamic> parsedTop5 = [];
    try {
      final data = jsonDecode(report.slidesJsonStr);
      if (data != null && data['topSongs'] != null) {
        parsedTop5 = data['topSongs'] as List<dynamic>;
      }
    } catch (_) {}

    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');
    return _Slide(
      gradient: theme.gradient,
      isBold: isBold,
      child: _Top5List(parsedTop5: parsedTop5, isBold: isBold, loadedSongs: loadedSongs),
    );
  }
}

class _Top5List extends StatelessWidget {
  final List<dynamic> parsedTop5;
  final bool isBold;
  final List<Song> loadedSongs;
  const _Top5List({required this.parsedTop5, this.isBold = false, required this.loadedSongs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Top 5 Songs',
              style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
          const SizedBox(height: 32),
          if (parsedTop5.isEmpty)
            const Center(child: Text("Not enough data to calculate top 5.", style: TextStyle(color: Colors.white70))),
          ...parsedTop5.take(5).toList().asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final item = entry.value;
            final songId = item['id'] as int?;
            
            final Song? song = loadedSongs.firstWhere((s) => s.id == songId, orElse: () => Song()..title = 'Unknown');

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    alignment: Alignment.centerLeft,
                    child: Text('$idx', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: song?.artBytes != null && song!.artBytes!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            Uint8List.fromList(song.artBytes!),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: 120,
                            cacheHeight: 120,
                          ),
                        )
                      : const Icon(Icons.music_note, color: Colors.white24, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['title'] ?? 'Unknown',
                          style: TextStyle(color: isBold ? Colors.black : Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${item['artist'] ?? 'Unknown'}',
                          style: TextStyle(color: isBold ? Colors.black.withOpacity(0.7) : Colors.white54, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${(item['minutes'] ?? 0).toInt()} mins',
                        style: const TextStyle(color: BopTheme.green, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      Text('${item['playCount'] ?? 0} plays',
                        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Card 6: Vibe Map ──────────────────────────────────────────
class _VibeMapCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _VibeMapCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    var genreMap = <String, int>{};
    try {
      genreMap = Map<String, int>.from(jsonDecode(report.genreJsonStr));
    } catch (_) {}

    final sortedGenres = genreMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedGenres.isEmpty) return const SizedBox.shrink();

    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');

    Widget content;
    List<dynamic> heatmapData = [];
    try {
      final slidesData = jsonDecode(report.slidesJsonStr);
      if (slidesData != null && slidesData['heatmap'] != null) {
        heatmapData = slidesData['heatmap'] as List<dynamic>;
      }
    } catch (_) {}

    if (heatmapData.isEmpty) {
      if (sortedGenres.length == 1) {
        content = _soloGenre(sortedGenres.first, isBold);
      } else {
        content = _multiGenre(sortedGenres.take(5).toList(), isBold);
      }
    } else {
      content = _MoodHeatmap(heatmapData: heatmapData, sortedGenres: sortedGenres, isBold: isBold);
    }

    return _Slide(
      gradient: theme.gradient,
      isBold: isBold,
      child: Stack(
        children: [
          _AbstractAnimation(
            shapeColor: theme.shapeColor,
            type: _AnimType.liquid,
            isBold: isBold,
            child: const SizedBox.expand(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('your mood heatmap',
                    style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
                const SizedBox(height: 32),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _soloGenre(MapEntry<String, int> entry, bool isBold) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isBold ? Colors.black : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: isBold ? null : Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.key,
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('${entry.value} plays this month',
              style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _multiGenre(List<MapEntry<String, int>> genres, bool isBold) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return Stack(
        children: [
          _bentoBox(genres[0].key, 0, 0, w * 0.6, h * 0.55, true, isBold),
          if (genres.length > 1) _bentoBox(genres[1].key, w * 0.6 + 12, 0, w * 0.4 - 12, h * 0.4, false, isBold),
          if (genres.length > 2) _bentoBox(genres[2].key, 0, h * 0.55 + 12, w * 0.6, h * 0.3, false, isBold),
          if (genres.length > 3) _bentoBox(genres[3].key, w * 0.6 + 12, h * 0.4 + 12, w * 0.4 - 12, h * 0.45 - 12, false, isBold),
        ],
      );
    });
  }

  Widget _bentoBox(String label, double left, double top, double width, double height, bool isLarge, bool isBold) {
    final color = _getVibeColors(label).first;
    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.7), width: 1),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: isLarge ? 22 : 15,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _getVibeColors(String genre) {
    final g = genre.toLowerCase();
    if (g.contains('pop')) return [Colors.pinkAccent, Colors.purpleAccent, Colors.deepPurple, Colors.blueAccent];
    if (g.contains('rock') || g.contains('metal') || g.contains('punk')) return [Colors.redAccent, Colors.orangeAccent, Colors.black87, Colors.blueGrey];
    if (g.contains('jazz') || g.contains('blues') || g.contains('soul')) return [Colors.blueAccent, Colors.indigo, Colors.black87, Colors.teal];
    if (g.contains('hip hop') || g.contains('rap') || g.contains('r&b')) return [Colors.orange, Colors.yellow, Colors.black87, Colors.brown];
    if (g.contains('electronic') || g.contains('dance') || g.contains('techno') || g.contains('house')) return [Colors.cyanAccent, Colors.blue, Colors.deepPurple, Colors.indigo];
    if (g.contains('chill') || g.contains('lofi') || g.contains('ambient')) return [Colors.tealAccent, Colors.green, Colors.black87, Colors.blueGrey];
    if (g.contains('classical') || g.contains('orchestra')) return [Colors.amber, Colors.brown, Colors.black87, Colors.grey];
    if (g.contains('country') || g.contains('folk')) return [Colors.brown, Colors.orange, Colors.green, Colors.yellow];
    if (g.contains('reggae') || g.contains('ska')) return [Colors.green, Colors.yellow, Colors.red, Colors.black87];
    if (g.contains('k-pop') || g.contains('j-pop')) return [Colors.pink, Colors.lightBlue, Colors.white, Colors.purple];
    if (g.contains('latin') || g.contains('reggaeton') || g.contains('salsa')) return [Colors.red, Colors.yellow, Colors.orange, Colors.orangeAccent];
    if (g.contains('indie') || g.contains('alternative')) return [Colors.teal, Colors.blueGrey, Colors.indigo, Colors.white70];
    if (g.contains('synthwave') || g.contains('vaporwave')) return [const Color(0xFFFF00FF), const Color(0xFF00FFFF), const Color(0xFF8A2BE2), Colors.black];
    if (g.contains('disco') || g.contains('funk')) return [Colors.purpleAccent, Colors.yellowAccent, Colors.cyan, Colors.pinkAccent];
    if (g.contains('hyperpop')) return [Colors.greenAccent, Colors.pinkAccent, Colors.yellowAccent, Colors.blueAccent];
    if (g.contains('acoustic') || g.contains('singer')) return [const Color(0xFFCD853F), const Color(0xFFF5DEB3), const Color(0xFF8B4513), Colors.white];
    return [BopTheme.green, Colors.blueAccent, Colors.purpleAccent, Colors.orangeAccent];
  }
}

// ── Card 7: Time Insight ──────────────────────────────────────
class _TimeInsightCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _TimeInsightCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');

    String insight = "${report.peakHourLabel} - The perfect hour.";
    try {
      final data = jsonDecode(report.slidesJsonStr);
      if (data['insights'] != null && data['insights']['timeInsight'] != null) {
        insight = data['insights']['timeInsight'];
      }
    } catch (_) {}

    return _Slide(
      isBold: isBold,
      gradient: theme.gradient,
      child: _AbstractAnimation(
        type: theme.yearlyType,
        shapeColor: theme.shapeColor,
        isBold: isBold,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_filled, color: theme.shapeColor, size: 64),
            const SizedBox(height: 32),
            const Text('Peak Listening Time', style: TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 8),
            Text(report.peakHourLabel, style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold)),
            const SizedBox(height: 64),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                insight,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontStyle: FontStyle.italic, fontWeight: FontWeight.w300),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card 8: Personality Insight ───────────────────────────────
// FIX: Added Center() wrapper + crossAxisAlignment.center + Padding guards
// to properly center AI-generated personality titles of any length.
class _PersonalityInsightCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _PersonalityInsightCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');

    String title = report.personalityType;
    try {
      final data = jsonDecode(report.slidesJsonStr);
      if (data['insights'] != null && data['insights']['personalityTitle'] != null) {
        title = data['insights']['personalityTitle'];
      }
    } catch (_) {}

    return _Slide(
      isBold: isBold,
      gradient: theme.gradient,
      child: _AbstractAnimation(
        type: theme.yearlyType,
        shapeColor: theme.shapeColor,
        isBold: isBold,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Your Listening Personality',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 48),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.shapeColor.withOpacity(0.2),
                  border: Border.all(color: theme.shapeColor.withOpacity(0.5), width: 2),
                ),
                child: Icon(_personalityIcon(report.personalityEmoji), color: Colors.white, size: 60),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Based on your ${_getTopGenre(report)} habits.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
              const SizedBox(height: 48),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Music is not optional.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalityCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _PersonalityCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(report.generatedAt.month, report.cadence == 'yearly');
    return _Slide(
      gradient: theme.gradient,
      isBold: isBold,
      child: _AbstractAnimation(
        shapeColor: theme.shapeColor,
        type: _AnimType.particles,
        isBold: isBold,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('your listening personality',
                  style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
              const SizedBox(height: 32),
              const Icon(Icons.music_note, color: Colors.white, size: 82),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(report.personalityType,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        letterSpacing: -1.5)),
              ),
              const SizedBox(height: 24),
              Text(
                'Peak listening: ${report.peakHourLabel}.\nSleeping is optional.\nMusic is not.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card 9: LLM Recap ─────────────────────────────────────────
class _LLMRecapCard extends StatelessWidget {
  final WrappedReport report;
  final bool isBold;
  const _LLMRecapCard({required this.report, required this.isBold});

  @override
  Widget build(BuildContext context) {
    final hasRecap = report.llmRecap.isNotEmpty;

    return _Slide(
      gradient: const LinearGradient(
        colors: [Color(0xFF16A085), Color(0xFF191414)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      isBold: isBold,
      child: _AbstractAnimation(
        shapeColor: Colors.lightGreen,
        type: _AnimType.waves,
        isBold: isBold,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${report.periodLabel.toLowerCase()} in words',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (hasRecap && report.isAiGenerated)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: BopTheme.green.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: BopTheme.green, size: 10),
                          SizedBox(width: 4),
                          Text('BOP AI', style: TextStyle(color: BopTheme.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else if (!hasRecap)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: BopTheme.green),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<String?>(
                valueListenable: LlmService.instance.modelStatus,
                builder: (context, status, _) {
                  return Text(
                    hasRecap
                        ? '"${report.llmRecap}"'
                        : (status ?? '"Generating your recap on-device…"'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.7,
                      fontStyle: FontStyle.italic,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                report.isAiGenerated ? 'AI-Driven Insight' : 'Listening Overview',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card 10: Share ────────────────────────────────────────────
class _ShareCard extends StatefulWidget {
  final WrappedReport report;
  final bool isBold;
  const _ShareCard({required this.report, required this.isBold});

  @override
  State<_ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends State<_ShareCard> {
  String _username = 'you';
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('username') ?? 'you';
    final avatar = prefs.getString('avatar_path');
    if (mounted) {
      setState(() {
        _username = name;
        _avatarPath = avatar;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = RecapTheme.get(widget.report.generatedAt.month, widget.report.cadence == 'yearly');
    return _Slide(
      gradient: theme.gradient,
      isBold: widget.isBold,
      child: Stack(
        children: [
          _AbstractAnimation(
            shapeColor: theme.shapeColor,
            type: _AnimType.blobs,
            isBold: widget.isBold,
            child: const SizedBox.expand(),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${widget.report.generatedAt.year.toString()} recap',
                    style: const TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
                const SizedBox(height: 32),
                if (_avatarPath != null)
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                      image: DecorationImage(image: FileImage(File(_avatarPath!)), fit: BoxFit.cover),
                    ),
                  )
                else
                  const CircleAvatar(
                    radius: 70,
                    backgroundColor: Colors.white12,
                    child: Icon(Icons.person, color: Colors.white54, size: 70),
                  ),
                const SizedBox(height: 24),
                Text(_username,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '${widget.report.totalMinutes} mins • ${widget.report.topArtist} • ${widget.report.personalityType}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 48),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ElevatedButton.icon(
                    onPressed: () => _shareRecap(context),
                    icon: const Icon(Icons.share, color: Colors.black, size: 20),
                    label: const Text('Share to Stories', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('made with Bop', style: TextStyle(color: Colors.white24, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRecap(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share your recap', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _shareOption(
                  icon: Icons.style,
                  label: 'Original Story',
                  onTap: () {
                    Navigator.pop(ctx);
                    _executeShare(context, isReceipt: false);
                  },
                ),
                _shareOption(
                  icon: Icons.receipt_long,
                  label: 'Music Receipt',
                  onTap: () {
                    Navigator.pop(ctx);
                    _executeShare(context, isReceipt: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _shareOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: BopTheme.green, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _executeShare(BuildContext context, {required bool isReceipt}) async {
    try {
      final theme = RecapTheme.get(widget.report.generatedAt.month, widget.report.cadence == 'yearly');
      
      Uint8List? bgBytes;
      if (isReceipt) {
        final data = await rootBundle.load('assets/images/receipt_bg.png');
        bgBytes = data.buffer.asUint8List();
      }

      final Widget summaryWidget = isReceipt 
          ? WrappedReceiptWidget(report: widget.report, username: _username, bgBytes: bgBytes)
          : _RecapSummaryCard(
              report: widget.report,
              theme: theme,
              username: _username,
              avatarPath: _avatarPath,
              isBold: widget.isBold,
            );

      await ShareService.shareWrappedRecap(context, summaryWidget, widget.report.periodLabel);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }
}

class _RecapSummaryCard extends StatelessWidget {
  final WrappedReport report;
  final RecapTheme theme;
  final String username;
  final String? avatarPath;
  final bool isBold;

  const _RecapSummaryCard({required this.report, required this.theme, required this.username, this.avatarPath, required this.isBold});

  @override
  Widget build(BuildContext context) {
    List<dynamic> top5 = [];
    try {
      final data = jsonDecode(report.slidesJsonStr);
      top5 = data['topSongs'] ?? [];
    } catch (_) {}

    Map<String, dynamic> genres = {};
    try {
      genres = jsonDecode(report.genreJsonStr) ?? {};
    } catch (_) {}
    final topGenres = genres.entries.toList()..sort((a, b) => (b.value as int).compareTo(a.value as int));

    return Material(
      color: Colors.black,
      child: Container(
        width: 360,
        height: 640,
        decoration: BoxDecoration(gradient: theme.gradient),
        child: Stack(
          children: [
            _AbstractAnimation(
              shapeColor: theme.shapeColor,
              type: report.cadence == 'yearly' ? _AnimType.nebula : theme.yearlyType,
              isBold: isBold,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          const Text('BOP RECAP', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 3)),
                          const SizedBox(height: 2),
                          Text(report.periodLabel.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        if (avatarPath != null && File(avatarPath!).existsSync())
                          CircleAvatar(radius: 20, backgroundImage: FileImage(File(avatarPath!)))
                        else
                          const CircleAvatar(radius: 20, backgroundColor: Colors.white12, child: Icon(Icons.person, color: Colors.white24, size: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(username, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _sectionHeader('Top Artist'),
                    Text(report.topArtist, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                    Text('${report.totalMinutes} total minutes', style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _sectionHeader('Top 5 Songs'),
                    ...top5.take(5).toList().asMap().entries.map((entry) {
                      final s = entry.value;
                      final i = entry.key + 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              child: Text('$i', style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w900)),
                            ),
                            FutureBuilder<Song?>(
                              future: s['id'] != null ? DbService.instance.isar.songs.get(s['id'] as int) : Future.value(null),
                              builder: (context, snap) {
                                final art = snap.data?.artBytes;
                                return Container(
                                  width: 32,
                                  height: 32,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: art != null && art.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.memory(Uint8List.fromList(art), fit: BoxFit.cover),
                                      )
                                    : const Icon(Icons.music_note, color: Colors.white24, size: 14),
                                );
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${s['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                                  Text('${s['artist']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('${(s['minutes'] ?? 0).toInt()} ${(s['minutes'] ?? 0).toInt() == 1 ? 'min' : 'mins'}',
                                style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('Style'),
                              Row(
                                children: [
                                  Icon(_personalityIcon(report.personalityEmoji), color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(report.personalityType, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('Genres'),
                              ...topGenres.take(2).map((g) => Text(g.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Center(child: Icon(Icons.music_note, color: Colors.white, size: 24)),
                    const Center(child: Text('Shared via Bop', style: TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
    );
  }
}

// ── Mood Heatmap ──────────────────────────────────────────────
class _MoodHeatmap extends StatefulWidget {
  final List<dynamic> heatmapData;
  final List<MapEntry<String, int>> sortedGenres;
  final bool isBold;

  const _MoodHeatmap({required this.heatmapData, required this.sortedGenres, this.isBold = false});

  @override
  State<_MoodHeatmap> createState() => _MoodHeatmapState();
}

class _MoodHeatmapState extends State<_MoodHeatmap> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hourlyIntensity = List.filled(24, 0);
    for (var day in widget.heatmapData) {
      if (day is List) {
        for (int h = 0; h < 24; h++) {
          if (h < day.length) hourlyIntensity[h] += (day[h] as num).toInt();
        }
      }
    }

    final maxVal = hourlyIntensity.fold<int>(0, (m, v) => v > m ? v : m).toDouble();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(double.infinity, double.infinity),
                painter: _MoodRadialPainter(
                  hourlyIntensity,
                  maxVal,
                  _controller.value * 2 * pi,
                  isBold: widget.isBold,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 48),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: widget.sortedGenres.take(3).map((e) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _MoodRadialPainter extends CustomPainter {
  final List<int> intensities;
  final double max;
  final double rotation;
  final bool isBold;

  _MoodRadialPainter(this.intensities, this.max, this.rotation, {this.isBold = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2.8;
    final paint = Paint()..style = PaintingStyle.fill;

    final segmentAngle = (2 * pi) / 24;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    for (int i = 0; i < 24; i++) {
      final val = intensities[i];
      final strength = max > 0 ? val / max : 0.0;
      final hRadius = radius + (strength * 40);

      Color color;
      if (i >= 22 || i <= 4) {
        color = Colors.deepPurpleAccent.withOpacity(0.5 + 0.5 * strength);
      } else if (i >= 5 && i <= 10) {
        color = Colors.orangeAccent.withOpacity(0.5 + 0.5 * strength);
      } else if (i >= 11 && i <= 16) {
        color = Colors.cyanAccent.withOpacity(0.5 + 0.5 * strength);
      } else {
        color = Colors.pinkAccent.withOpacity(0.5 + 0.5 * strength);
      }

      if (isBold) color = color.withOpacity(0.9);

      paint.color = color;

      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: hRadius),
        i * segmentAngle,
        segmentAngle * 0.9,
        true,
        paint,
      );
    }

    paint.shader = const RadialGradient(
      colors: [Colors.black54, Colors.transparent],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius * 0.8));
    canvas.drawCircle(Offset.zero, radius * 0.8, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MoodRadialPainter old) => old.rotation != rotation;
}

String _getTopGenre(WrappedReport report) {
  try {
    final Map<String, dynamic> genres = jsonDecode(report.genreJsonStr);
    if (genres.isEmpty) return 'eclectic';
    var top = genres.entries.first;
    for (var e in genres.entries) {
      if ((e.value as num) > (top.value as num)) top = e;
    }
    return top.key;
  } catch (_) {
    return 'eclectic';
  }
}