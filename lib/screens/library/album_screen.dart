import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../theme/app_theme.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/animated_equalizer.dart';
import '../player/now_playing_screen.dart';
import '../../services/share_service.dart';
import '../../models/playlist.dart';

class AlbumScreen extends ConsumerStatefulWidget {
  final String albumName;
  final String artist;

  const AlbumScreen({
    super.key,
    required this.albumName,
    required this.artist,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen>
    with SingleTickerProviderStateMixin {
  Color _dominantColor = const Color(0xFF333333);
  bool _colorExtracted = false;

  Future<void> _extractColor(List<int> artBytes) async {
    if (_colorExtracted) return;
    _colorExtracted = true;
    final provider = ResizeImage(MemoryImage(Uint8List.fromList(artBytes)), width: 100);
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 6,
        size: const Size(80, 80),
      );
      final color = palette.dominantColor?.color ?? palette.vibrantColor?.color ?? const Color(0xFF333333);
      if (mounted) setState(() => _dominantColor = color);
    } catch (_) {}
  }

  Widget build(BuildContext context) {
    final albumSongsAsync = ref.watch(albumSongsProvider(widget.albumName));
    final playerState = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: BopTheme.background,
      body: albumSongsAsync.when(
        data: (albumSongs) {

          final artSong = albumSongs.cast<Song?>().firstWhere(
            (s) => s!.artBytes != null && s.artBytes!.isNotEmpty,
            orElse: () => null,
          );
          final artBytes = artSong?.artBytes;

          if (artBytes != null && artBytes.isNotEmpty) {
            _extractColor(artBytes);
          }

          final isAlbumPlaying = albumSongs.any((s) => s.id == playerState.currentSong?.id) && playerState.isPlaying;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 340,
                pinned: true,
                backgroundColor: _dominantColor,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_dominantColor, BopTheme.background],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: artBytes == null || artBytes.isEmpty
                                ? Container(
                                    color: _dominantColor.withOpacity(0.5),
                                    child: const Icon(Icons.album, color: Colors.white38, size: 80),
                                  )
                                : Image.memory(
                                    Uint8List.fromList(artBytes),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    cacheWidth: 800,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.albumName,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.artist} • Album',
                        style: const TextStyle(color: BopTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${albumSongs.length} songs',
                        style: const TextStyle(color: BopTheme.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.share_outlined, color: BopTheme.textSecondary, size: 28),
                            onPressed: () {
                              final pseudoPlaylist = Playlist()..name = widget.albumName;
                              ShareService.sharePlaylistReceipt(context, pseudoPlaylist, songs: albumSongs);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: BopTheme.textSecondary, size: 28),
                            onPressed: () => _showAlbumOptions(context, ref, albumSongs),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.shuffle, color: BopTheme.textSecondary, size: 28),
                            onPressed: () => ref.read(playerProvider.notifier).shufflePlay(albumSongs),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () {
                              if (isAlbumPlaying) {
                                ref.read(playerProvider.notifier).togglePlayPause();
                              } else if (albumSongs.isNotEmpty) {
                                ref.read(playerProvider.notifier).playQueue(albumSongs);
                              }
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(color: BopTheme.green, shape: BoxShape.circle),
                              child: Icon(isAlbumPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 30),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = albumSongs[index];
                    final isPlaying = playerState.currentSong?.id == song.id;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      leading: SizedBox(
                        width: 32,
                        child: Center(
                          child: isPlaying && playerState.isPlaying
                              ? const AnimatedEqualizer(color: BopTheme.green, size: 16)
                              : isPlaying
                                  ? const Icon(Icons.equalizer, color: BopTheme.green, size: 16)
                                  : Text('${index + 1}', style: const TextStyle(color: BopTheme.textMuted, fontSize: 13)),
                        ),
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(color: isPlaying ? BopTheme.green : BopTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
                      onTap: () {
                        ref.read(playerProvider.notifier).playQueue(albumSongs, startIndex: index);
                      },
                    );
                  },
                  childCount: albumSongs.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Error loading album', style: TextStyle(color: Colors.white))),
      ),
    );
  }

  void _showAlbumOptions(BuildContext context, WidgetRef ref, List<Song> songs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Colors.white70),
            title: const Text('Add to Queue', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              for (final s in songs) {
                ref.read(playerProvider.notifier).addToQueue(s);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share, color: Colors.white70),
            title: const Text('Share Album', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              final pseudoPlaylist = Playlist()..name = widget.albumName;
              ShareService.sharePlaylistReceipt(context, pseudoPlaylist, songs: songs);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
