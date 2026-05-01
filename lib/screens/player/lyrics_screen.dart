import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../models/song.dart';
import '../../providers/stats_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/lrc_parser.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  final Song song;
  final Color? dominantColor;
  const LyricsScreen({super.key, required this.song, this.dominantColor});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsAsync = ref.watch(lyricsProvider(widget.song));
    // Optimization: Selective watching to avoid rebuilding entire screen on every frame
    final position = ref.watch(positionProvider).value ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              (widget.dominantColor ?? BopTheme.background).withOpacity(0.5),
              Colors.black,
            ],
            stops: const [0.0, 0.7],
          ),
        ),
        child: SafeArea(
        child: lyricsAsync.when(
          data: (lyrics) {
            if (lyrics == null || lyrics.isEmpty) {
              return _emptyState();
            }

            final lines = LrcParser.parse(lyrics);
            if (lines.isEmpty) return _emptyState();

            // Find current active line.
            final adjustedPosition = position;
            int activeIndex = -1;
            for (int i = 0; i < lines.length; i++) {
              if (adjustedPosition >= lines[i].timestamp) {
                activeIndex = i;
              } else {
                break;
              }
            }

            // Auto-scroll logic: centers the active line in the viewport
            if (activeIndex != _currentIndex && activeIndex != -1) {
              _currentIndex = activeIndex;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  final viewportHeight = _scrollController.position.viewportDimension;
                  final lineHeight = 60.0; // matched with padding/font
                  final targetOffset = (activeIndex * lineHeight) - (viewportHeight / 2) + (lineHeight / 2);
                  
                  _scrollController.animateTo(
                    targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                  );
                }
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: BopTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    itemCount: lines.length,
                    itemBuilder: (_, i) {
                      final isActive = i == activeIndex;
                      final distance = (i - activeIndex).abs();
                      final targetOpacity = isActive ? 1.0 : (distance == 1 ? 0.5 : 0.25);
                      final targetSize = isActive ? 26.0 : (distance == 1 ? 19.0 : 16.0);
                      final targetWeight = isActive ? FontWeight.w800 : FontWeight.w600;

                      return InkWell(
                        onTap: () {
                          if (lines[i].timestamp != Duration.zero) {
                            ref.read(playerProvider.notifier).seek(lines[i].timestamp);
                          }
                        },
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: targetOpacity),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (context, opacity, child) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween(end: targetSize),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              builder: (context, fontSize, _) {
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutCubic,
                                  padding: EdgeInsets.symmetric(
                                    vertical: isActive ? 16 : 10,
                                  ),
                                  child: Transform.scale(
                                    scale: isActive ? 1.0 : 0.95,
                                    alignment: Alignment.centerLeft,
                                    child: Opacity(
                                      opacity: opacity,
                                      child: Text(
                                        lines[i].text,
                                        style: TextStyle(
                                          fontSize: fontSize,
                                          fontWeight: targetWeight,
                                          color: BopTheme.textPrimary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: BopTheme.green),
          ),
          error: (e, __) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: BopTheme.red)),
          ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note, color: Colors.white24, size: 48),
          const SizedBox(height: 16),
          Text('Lyrics not available',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BopTheme.textMuted)),
          const SizedBox(height: 8),
          Text(widget.song.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
