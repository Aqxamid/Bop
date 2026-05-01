// screens/player/now_playing_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:text_scroll/text_scroll.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/app_theme.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../services/db_service.dart';
import '../../widgets/song_option_widgets.dart';
import '../../services/lrc_parser.dart';
import '../../services/share_service.dart';
import '../../providers/stats_provider.dart';
import '../../providers/settings_provider.dart';
import '../library/album_screen.dart';
import 'lyrics_screen.dart';

/// Color cache so we don't re-extract for the same song
final _dominantColorCache = <int, Color>{};

Future<Color> _extractColor(List<int> artBytes) async {
  final provider = ResizeImage(MemoryImage(Uint8List.fromList(artBytes)), width: 100);
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      provider,
      maximumColorCount: 6,
      size: const Size(80, 80),
    );
    return palette.dominantColor?.color ??
        palette.vibrantColor?.color ??
        const Color(0xFF333333);
  } catch (_) {
    return const Color(0xFF333333);
  }
}

class NowPlayingScreen extends ConsumerStatefulWidget {
  final Song song;
  const NowPlayingScreen({super.key, required this.song});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  Color _dominantColor = const Color(0xFF333333);
  late AnimationController _playPauseController;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final isPlaying = ref.read(playerProvider).isPlaying;
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: isPlaying ? 1.0 : 0.0,
    );
    _pageController = PageController(initialPage: ref.read(playerProvider).currentIndex);
    _extractDominant(widget.song);
  }

  @override
  void dispose() {
    _playPauseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _extractDominant(Song song) async {
    if (song.artBytes == null || song.artBytes!.isEmpty) return;
    if (_dominantColorCache.containsKey(song.id)) {
      setState(() => _dominantColor = _dominantColorCache[song.id]!);
      return;
    }
    final color = await _extractColor(song.artBytes!);
    _dominantColorCache[song.id] = color;
    if (mounted) setState(() => _dominantColor = color);
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong ?? widget.song;
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;

    // Using ref.listen for side effects is more efficient than build-time checks
    ref.listen(playerProvider, (previous, next) {
      if (previous?.currentSong?.id != next.currentSong?.id) {
        if (next.currentSong != null) _extractDominant(next.currentSong!);
      }
      
      if (previous?.isPlaying != next.isPlaying) {
        if (next.isPlaying) _playPauseController.forward();
        else _playPauseController.reverse();
      }

      if (_pageController.hasClients && next.currentIndex != _pageController.page?.round()) {
         _pageController.jumpToPage(next.currentIndex);
      }
    });

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
                Navigator.of(context).pop();
              }
            },
            child: _NowPlayingContent(song: song, dominantColor: _dominantColor, pageController: _pageController),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingContent extends ConsumerWidget {
  final Song song;
  final Color dominantColor;
  final PageController pageController;
  const _NowPlayingContent({required this.song, required this.dominantColor, required this.pageController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final isPlaying = playerState.isPlaying;
    final duration = playerState.duration;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            dominantColor.withOpacity(0.8),
            Colors.black,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
              // ── Top bar ───────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Flexible(
                      child: Column(
                        children: [
                          Text(
                            'NOW PLAYING',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            playerState.currentSong?.title ?? song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onPressed: () => _showContextMenu(context, song),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Album art ─────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: playerState.queue.isEmpty ? 1 : playerState.queue.length,
                    onPageChanged: (index) {
                      if (index != playerState.currentIndex) {
                        ref.read(playerProvider.notifier).skipTo(index);
                      }
                      
                      // ── Preloading: Precache next 2 artworks ────────
                      final queue = playerState.queue;
                      if (queue.isNotEmpty) {
                        for (int i = 1; i <= 2; i++) {
                          final nextIdx = index + i;
                          if (nextIdx < queue.length) {
                            final nextSong = queue[nextIdx];
                            if (nextSong.artBytes != null && nextSong.artBytes!.isNotEmpty) {
                              precacheImage(
                                MemoryImage(Uint8List.fromList(nextSong.artBytes!)),
                                context,
                              );
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (context, index) {
                      final displaySong = playerState.queue.isEmpty ? song : playerState.queue[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: BopTheme.surfaceAlt,
                        ),
                        child: displaySong.artBytes != null && displaySong.artBytes!.isNotEmpty
                            ? Image.memory(
                                Uint8List.fromList(displaySong.artBytes!),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                alignment: Alignment.center,
                                cacheWidth: 800,
                              )
                            : _PlaceholderArt(title: displaySong.title),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Title + like ──────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playerState.currentSong?.title ?? song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            playerState.currentSong?.artist ?? song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        (playerState.currentSong?.isLiked ?? song.isLiked) ? Icons.check_circle : Icons.add_circle_outline,
                        color: (playerState.currentSong?.isLiked ?? song.isLiked) ? BopTheme.green : Colors.white,
                        size: 28,
                      ),
                      onPressed: () => ref.read(playerProvider.notifier).toggleLike(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Progress bar ──────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Consumer(
                  builder: (context, ref, _) {
                    final position = ref.watch(positionProvider).value ?? Duration.zero;
                    final progress = duration.inMilliseconds > 0
                        ? position.inMilliseconds / duration.inMilliseconds
                        : 0.0;
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white.withOpacity(0.15),
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0),
                            onChanged: (v) {
                              final newPos = Duration(milliseconds: (v * duration.inMilliseconds).toInt());
                              ref.read(playerProvider.notifier).seek(newPos);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(_formatDuration(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // ── Controls Row ──────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle, color: playerState.shuffleEnabled ? BopTheme.green : Colors.white, size: 28),
                      onPressed: () => ref.read(playerProvider.notifier).toggleShuffle(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white, size: 44),
                      onPressed: () => ref.read(playerProvider.notifier).skipPrevious(),
                    ),
                    GestureDetector(
                      onTap: () => ref.read(playerProvider.notifier).togglePlayPause(),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Center(
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white, size: 44),
                      onPressed: () => ref.read(playerProvider.notifier).skipNext(),
                    ),
                    IconButton(
                      icon: Icon(
                        playerState.repeatMode == PlayerRepeatMode.one ? Icons.repeat_one : Icons.repeat,
                        color: playerState.repeatMode != PlayerRepeatMode.off ? BopTheme.green : Colors.white,
                        size: 28,
                      ),
                      onPressed: () => ref.read(playerProvider.notifier).toggleRepeat(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Bottom Icons Row (Share, Queue) ──────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final isGapless = ref.watch(settingsProvider.select((s) => s.gaplessPlayback));
                        return IconButton(
                          icon: Icon(
                            isGapless ? Icons.auto_awesome_motion : Icons.auto_awesome_motion_outlined,
                            color: isGapless ? BopTheme.green : Colors.white70,
                            size: 20,
                          ),
                          tooltip: 'Gapless Playback',
                          onPressed: () => ref.read(settingsProvider.notifier).setGaplessPlayback(!isGapless),
                        );
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 20),
                      onPressed: () {
                        ShareService.shareSongCard(context, song);
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.queue_music, color: Colors.white70, size: 20),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: const Color(0xFF181818),
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (_) => const _QueueModal(),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Lyrics Section ───────────
              _FullLyrics(song: playerState.currentSong ?? song, dominantColor: dominantColor),
              
              SizedBox(height: MediaQuery.of(context).padding.bottom + 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _QueueModal extends ConsumerWidget {
  const _QueueModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final queue = playerState.queue;
    final isShuffled = playerState.shuffleEnabled;
    final effectiveIndices = (isShuffled && playerState.effectiveIndices != null && playerState.effectiveIndices!.length == queue.length)
        ? playerState.effectiveIndices!
        : List.generate(queue.length, (i) => i);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.top + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Up Next',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${queue.length} songs',
                    style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: isShuffled
              ? ListView.builder(
                  itemCount: queue.length,
                  itemBuilder: (context, uiIndex) {
                    final realIndex = effectiveIndices[uiIndex];
                    final song = queue[realIndex];
                    final isCurrent = realIndex == playerState.currentIndex;
                    return _buildSongTile(context, ref, song, realIndex, isCurrent, isShuffled);
                  },
                )
              : ReorderableListView.builder(
                  itemCount: queue.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    ref.read(playerProvider.notifier).moveQueueItem(oldIndex, newIndex);
                  },
                  itemBuilder: (context, uiIndex) {
                    final realIndex = effectiveIndices[uiIndex];
                    final song = queue[realIndex];
                    final isCurrent = realIndex == playerState.currentIndex;
                    return _buildSongTile(context, ref, song, realIndex, isCurrent, isShuffled);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongTile(BuildContext context, WidgetRef ref, Song song, int realIndex, bool isCurrent, bool isShuffled) {
    return ListTile(
      key: ValueKey('queue_${song.id}_$realIndex'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 40,
          height: 40,
          child: song.artBytes != null && song.artBytes!.isNotEmpty
              ? Image.memory(
                  Uint8List.fromList(song.artBytes!),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: 80,
                  cacheHeight: 80,
                )
              : Container(color: Colors.grey[900], child: const Icon(Icons.music_note, color: Colors.white24, size: 20)),
        ),
      ),
      title: Text(song.title,
          style: TextStyle(
              color: isCurrent ? BopTheme.green : Colors.white,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist,
          style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCurrent)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
              onPressed: () => ref.read(playerProvider.notifier).removeFromQueue(realIndex),
            ),
          if (!isShuffled)
            ReorderableDragStartListener(
              index: realIndex,
              child: const Icon(Icons.reorder, color: Colors.white24),
            ),
        ],
      ),
      onTap: () {
        ref.read(playerProvider.notifier).skipTo(realIndex);
      },
    );
  }
}
class _FullLyrics extends ConsumerStatefulWidget {
  final Song song;
  final Color dominantColor;
  const _FullLyrics({required this.song, required this.dominantColor});

  @override
  ConsumerState<_FullLyrics> createState() => _FullLyricsState();
}

class _FullLyricsState extends ConsumerState<_FullLyrics> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActive(int index) {
    if (index != _lastActiveIndex && index >= 0) {
      _lastActiveIndex = index;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          index * 40.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyricsAsync = ref.watch(lyricsProvider(widget.song));
    final position = ref.watch(positionProvider).value ?? Duration.zero;

    final cardColor = HSLColor.fromColor(widget.dominantColor)
        .withLightness(0.15)
        .withSaturation(0.3)
        .toColor();

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LyricsScreen(song: widget.song, dominantColor: widget.dominantColor),
          ),
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: lyricsAsync.when(
          data: (lyrics) {
            if (lyrics == null || lyrics.isEmpty) return const Center(child: Text('No lyrics found', style: TextStyle(color: Colors.white54)));
            final lines = LrcParser.parse(lyrics);
            if (lines.isEmpty) return const Center(child: Text('No lyrics found', style: TextStyle(color: Colors.white54)));

            int activeIndex = -1;
            for (int i = 0; i < lines.length; i++) {
              if (position >= lines[i].timestamp) activeIndex = i;
              else break;
            }
            _scrollToActive(activeIndex);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('LYRICS', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    Icon(Icons.fullscreen, color: Colors.white.withOpacity(0.4), size: 20),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: lines.asMap().entries.map((entry) {
                        final i = entry.key;
                        final line = entry.value;
                        final isActive = i == activeIndex;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            line.text,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isActive ? Colors.white : Colors.white.withOpacity(0.2),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.white24)),
          error: (_, __) => const Center(child: Text('Error loading lyrics', style: TextStyle(color: Colors.white54))),
        ),
      ),
    );
  }
}
class _PlaceholderArt extends StatelessWidget {
  final String title;
  const _PlaceholderArt({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFC0392B),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0] : '♪',
          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Color(0xFFF1C40F)),
        ),
      ),
    );
  }
}

void _showContextMenu(BuildContext context, Song song) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF282828),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ContextMenu(song: song),
  );
}

class _ContextMenu extends ConsumerWidget {
  final Song song;
  const _ContextMenu({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final currentSongRef = playerState.currentSong;
    final currentSong = (currentSongRef != null && currentSongRef.id == song.id)
        ? currentSongRef
        : song;

    final items = [
      (
        currentSong.isLiked ? Icons.favorite : Icons.favorite_border,
        currentSong.isLiked ? 'Unlike' : 'Like',
        () => ref.read(playerProvider.notifier).toggleLike()
      ),
      (Icons.playlist_add, 'Add to playlist', () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF282828),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => PlaylistSelector(song: currentSong),
        );
      }),
      (Icons.queue_music, 'Add to queue', () {
        ref.read(playerProvider.notifier).addToQueue(currentSong);
      }),
      (Icons.share, 'Share', () {
        ShareService.shareSongCard(context, currentSong);
      }),
      (Icons.album, 'View album', () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlbumScreen(albumName: currentSong.album, artist: currentSong.artist),
          ),
        );
      }),
    ];

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: currentSong.artBytes != null && currentSong.artBytes!.isNotEmpty
                        ? Image.memory(
                            Uint8List.fromList(currentSong.artBytes!),
                            fit: BoxFit.cover,
                            cacheWidth: 100,
                            cacheHeight: 100,
                          )
                        : const ColoredBox(color: Color(0xFFC0392B)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(currentSong.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(currentSong.artist,
                          style: const TextStyle(
                              color: BopTheme.textSecondary,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF333333), height: 1),
          ...items.map((item) => ListTile(
                leading: Icon(item.$1, color: BopTheme.textSecondary, size: 20),
                title: Text(item.$2, style: const TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  item.$3();
                },
              )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
