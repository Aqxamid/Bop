// screens/library/playlist_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../theme/app_theme.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/stats_provider.dart';
import '../../services/db_service.dart';
import '../../services/share_service.dart';
import '../../widgets/animated_equalizer.dart';
import '../../widgets/playlist_cover_widget.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  final Playlist playlist;
  final List<Song>? initialSongs;

  const PlaylistScreen({
    super.key,
    required this.playlist,
    this.initialSongs,
  });

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen>
    with SingleTickerProviderStateMixin {
  Color _dominantColor = const Color(0xFF333333);
  bool _colorExtracted = false;

  @override
  void initState() {
    super.initState();
    try {
      _dominantColor = Color(int.parse(widget.playlist.coverColor.replaceFirst('#', '0xFF')));
    } catch (_) {}
  }

  Future<void> _extractColor(List<int> artBytes) async {
    if (_colorExtracted) return;
    _colorExtracted = true;
    final provider = MemoryImage(Uint8List.fromList(artBytes));
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 6,
        size: const Size(80, 80),
      );
      final color = palette.dominantColor?.color ?? palette.vibrantColor?.color ?? _dominantColor;
      if (mounted) setState(() => _dominantColor = color);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(allSongsProvider);
    final playlistSongs = widget.initialSongs ?? widget.playlist.songs.toList();
    final playerState = ref.watch(playerProvider);

    final artSong = playlistSongs.cast<Song?>().firstWhere(
      (s) => s!.artBytes != null && s.artBytes!.isNotEmpty,
      orElse: () => null,
    );
    if (artSong?.artBytes != null && artSong!.artBytes!.isNotEmpty) {
      _extractColor(artSong.artBytes!);
    }

    final isPlaylistPlaying = playlistSongs.any((s) => s.id == playerState.currentSong?.id) && playerState.isPlaying;

    return Scaffold(
      backgroundColor: BopTheme.background,
      body: CustomScrollView(
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
                      child: PlaylistCoverWidget(playlist: widget.playlist, size: 280, songs: playlistSongs),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.playlist.name,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlistSongs.length} songs',
                    style: const TextStyle(color: BopTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share_outlined, color: BopTheme.textSecondary, size: 26),
                        onPressed: () => ShareService.sharePlaylistReceipt(context, widget.playlist),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: BopTheme.textSecondary, size: 26),
                        onPressed: () => _showPlaylistOptions(context, ref),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: playerState.shuffleEnabled ? BopTheme.green : BopTheme.textSecondary,
                          size: 26,
                        ),
                        onPressed: () => ref.read(playerProvider.notifier).toggleShuffle(),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () {
                          if (isPlaylistPlaying) {
                            ref.read(playerProvider.notifier).togglePlayPause();
                          } else if (playlistSongs.isNotEmpty) {
                            ref.read(playerProvider.notifier).playQueue(playlistSongs);
                          }
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(color: BopTheme.green, shape: BoxShape.circle),
                          child: Icon(isPlaylistPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 30),
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
                final song = playlistSongs[index];
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
                  subtitle: Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert, color: BopTheme.textSecondary, size: 20),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: const Color(0xFF282828),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        builder: (_) => _PlaylistSongMenu(song: song, playlist: widget.playlist),
                      );
                    },
                  ),
                  onTap: () {
                    ref.read(playerProvider.notifier).playQueue(playlistSongs, startIndex: index);
                  },
                );
              },
              childCount: playlistSongs.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, WidgetRef ref) {
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
            title: const Text('Share Playlist', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ShareService.sharePlaylistReceipt(context, widget.playlist);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: BopTheme.red),
            title: const Text('Delete Playlist', style: TextStyle(color: BopTheme.red)),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF282828),
                  title: const Text('Delete Playlist', style: TextStyle(color: Colors.white)),
                  content: const Text('Are you sure you want to delete this playlist?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary))),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: BopTheme.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await DbService.instance.deletePlaylist(widget.playlist.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PlaylistSongMenu extends ConsumerWidget {
  final Song song;
  final Playlist playlist;
  const _PlaylistSongMenu({required this.song, required this.playlist});

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
            leading: const Icon(Icons.remove_circle_outline, color: BopTheme.red, size: 20),
            title: const Text('Remove from Playlist', style: TextStyle(color: BopTheme.red, fontSize: 14)),
            onTap: () async {
              Navigator.pop(context);
              await DbService.instance.removeSongFromPlaylist(playlist.id, song.id);
              ref.invalidate(allSongsProvider);
              if (context.mounted) Navigator.pop(context);
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
