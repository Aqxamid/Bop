import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../theme/app_theme.dart';
import '../../models/song.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/animated_equalizer.dart';
import '../player/now_playing_screen.dart';
import '../../services/db_service.dart';
import '../../services/share_service.dart';
import '../../widgets/song_option_widgets.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  final String artistName;

  const ArtistScreen({
    super.key,
    required this.artistName,
  });

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen>
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

  @override
  Widget build(BuildContext context) {
    final allSongs = ref.watch(allSongsProvider);
    final playerState = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: BopTheme.background,
      body: allSongs.when(
        data: (songs) {
          final artistSongs = songs
              .where((s) => s.artist.toLowerCase() == widget.artistName.toLowerCase())
              .toList();

          final artSong = artistSongs.cast<Song?>().firstWhere(
            (s) => s!.artBytes != null && s.artBytes!.isNotEmpty,
            orElse: () => null,
          );
          final artBytes = artSong?.artBytes;

          if (artBytes != null && artBytes.isNotEmpty) {
            _extractColor(artBytes);
          }

          final isArtistPlaying = artistSongs.any((s) => s.id == playerState.currentSong?.id) && playerState.isPlaying;

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
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: artBytes == null || artBytes.isEmpty
                                ? Container(
                                    color: _dominantColor.withOpacity(0.5),
                                    child: const Icon(Icons.person, color: Colors.white38, size: 80),
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
                        widget.artistName,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${artistSongs.length} songs',
                        style: const TextStyle(color: BopTheme.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.share_outlined, color: BopTheme.textSecondary, size: 28),
                            onPressed: () {
                              final pseudo = Playlist()..name = widget.artistName;
                              ShareService.sharePlaylistReceipt(context, pseudo, songs: artistSongs);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: BopTheme.textSecondary, size: 28),
                            onPressed: () => _showArtistOptions(context, ref, artistSongs),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.shuffle, color: BopTheme.textSecondary, size: 28),
                            onPressed: () {
                              if (artistSongs.isNotEmpty) {
                                ref.read(playerProvider.notifier).shufflePlay(artistSongs);
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () {
                              if (isArtistPlaying) {
                                ref.read(playerProvider.notifier).togglePlayPause();
                              } else if (artistSongs.isNotEmpty) {
                                ref.read(playerProvider.notifier).playQueue(artistSongs, startIndex: 0);
                              }
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(color: BopTheme.green, shape: BoxShape.circle),
                              child: Icon(isArtistPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 30),
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
                    final song = artistSongs[index];
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
                      subtitle: Text(song.album, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert, color: BopTheme.textSecondary, size: 20),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: const Color(0xFF282828),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                            builder: (_) => _ArtistSongMenu(song: song),
                          );
                        },
                      ),
                      onTap: () {
                        ref.read(playerProvider.notifier).playQueue(artistSongs, startIndex: index);
                      },
                    );
                  },
                  childCount: artistSongs.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Error loading artist', style: TextStyle(color: Colors.white))),
      ),
    );
  }

  void _showArtistOptions(BuildContext context, WidgetRef ref, List<Song> songs) {
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
            leading: const Icon(Icons.share, color: Colors.white70),
            title: const Text('Share Artist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              final pseudo = Playlist()..name = widget.artistName;
              ShareService.sharePlaylistReceipt(context, pseudo, songs: songs);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music, color: BopTheme.textSecondary),
            title: const Text('Add all to queue', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              for (final s in songs) {
                ref.read(playerProvider.notifier).addToQueue(s);
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ArtistSongMenu extends ConsumerWidget {
  final Song song;
  const _ArtistSongMenu({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    child: song.artBytes != null && song.artBytes!.isNotEmpty
                        ? Image.memory(Uint8List.fromList(song.artBytes!), fit: BoxFit.cover, cacheWidth: 88, cacheHeight: 88)
                        : const ColoredBox(color: Color(0xFFC0392B)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF333333), height: 1),
          ListTile(
            leading: Icon(song.isLiked ? Icons.favorite : Icons.favorite_border, color: song.isLiked ? BopTheme.green : BopTheme.textSecondary, size: 20),
            title: Text(song.isLiked ? 'Unlike' : 'Like', style: const TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () async {
              Navigator.pop(context);
              await DbService.instance.toggleLike(song.id);
              ref.invalidate(allSongsProvider);
              ref.read(playerProvider.notifier).refreshCurrentSong();
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: BopTheme.textSecondary, size: 20),
            title: const Text('Add to playlist', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF282828),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => PlaylistSelector(song: song),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music, color: BopTheme.textSecondary, size: 20),
            title: const Text('Add to queue', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              ref.read(playerProvider.notifier).addToQueue(song);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
