// widgets/mini_player.dart
// Persistent mini player bar at the bottom of every tab screen.
// Features: rounded corners, cover-based gradient, marquee text, progress bar.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:text_scroll/text_scroll.dart';
import '../theme/app_theme.dart';
import '../providers/player_provider.dart';
import '../screens/player/now_playing_screen.dart';

/// Caches extracted dominant color per song id to avoid re-computing.
final _colorCache = <int, Color>{};

Future<Color> _extractDominantColor(List<int> artBytes) async {
  final imageProvider = MemoryImage(Uint8List.fromList(artBytes));
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

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  Color _dominantColor = BopTheme.surface;
  int? _lastSongId;

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

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    // Don't show if nothing is playing
    if (song == null) return const SizedBox.shrink();

    // Extract color from art
    if (song.artBytes != null && song.artBytes!.isNotEmpty) {
      _updateColor(song.id, song.artBytes!);
    }

    final position = playerState.position;
    final duration = playerState.duration;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < 0) {
            ref.read(playerProvider.notifier).skipNext();
          } else if (details.primaryVelocity! > 0) {
            ref.read(playerProvider.notifier).skipPrevious();
          }
        }
      },
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < 0) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
          } else if (details.primaryVelocity! > 0) {
            ref.read(playerProvider.notifier).stop();
          }
        }
      },
      child: InkWell(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                      ),
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

                    // Song info
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
                child: Container(
                  height: 2,
                  color: Colors.white.withOpacity(0.1),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
