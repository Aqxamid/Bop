// widgets/mini_player.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:text_scroll/text_scroll.dart';
import '../theme/app_theme.dart';
import '../providers/player_provider.dart';
import '../screens/player/now_playing_screen.dart';

final _colorCache = <int, Color>{};

Future<Color> _extractDominantColor(List<int> artBytes) async {
  final imageProvider = ResizeImage(MemoryImage(Uint8List.fromList(artBytes)), width: 100);
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      imageProvider,
      maximumColorCount: 6,
      size: const Size(50, 50),
    );
    return palette.dominantColor?.color ?? BopTheme.surface;
  } catch (_) {
    return BopTheme.surface;
  }
}

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  Color _dominantColor = BopTheme.surface;
  int? _lastSongId;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1.5),
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _updateColor(int songId, List<int> artBytes) async {
    if (_lastSongId == songId) return;
    _lastSongId = songId;
    if (_colorCache.containsKey(songId)) {
      if (mounted) setState(() => _dominantColor = _colorCache[songId]!);
      return;
    }
    final color = await _extractDominantColor(artBytes);
    _colorCache[songId] = color;
    if (mounted) setState(() => _dominantColor = color);
  }

  Future<void> _swipeDownToClose() async {
    await _slideController.forward();
    ref.read(playerProvider.notifier).stop();
    _slideController.reset();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();

    if (song.artBytes != null && song.artBytes!.isNotEmpty) {
      _updateColor(song.id, song.artBytes!);
    }

    return SlideTransition(
      position: _slideAnimation,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300) {
            ref.read(playerProvider.notifier).skipNext();
          } else if (details.primaryVelocity! > 300) {
            ref.read(playerProvider.notifier).skipPrevious();
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! > 300) {
            _swipeDownToClose();
          } else if (details.primaryVelocity! < -300) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
          }
        },
        child: InkWell(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _dominantColor.withOpacity(0.9),
                  const Color(0xFF1A1A1A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: song.artBytes != null && song.artBytes!.isNotEmpty
                              ? Image.memory(
                                  Uint8List.fromList(song.artBytes!),
                                  key: ValueKey('mini_art_${song.id}'),
                                  cacheWidth: 88,
                                  cacheHeight: 88,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Container(color: BopTheme.surfaceAlt),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextScroll(
                              song.title,
                              velocity: const Velocity(pixelsPerSecond: Offset(30, 0)),
                              style: const TextStyle(
                                color: BopTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              song.artist,
                              style: const TextStyle(
                                color: BopTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () => ref.read(playerProvider.notifier).togglePlayPause(),
                      ),
                    ],
                  ),
                ),
                // Progress bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final position = ref.watch(positionProvider).value ?? Duration.zero;
                      final duration = playerState.duration;
                      final progress = duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;

                      return Container(
                        height: 2,
                        color: Colors.white.withOpacity(0.1),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(color: Colors.white.withOpacity(0.5)),
                        ),
                      );
                    },
                  ),
                ),
                // Drag handle hint
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
