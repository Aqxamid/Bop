// screens/library/library_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mini_player.dart';
import '../../providers/stats_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/scanner_service.dart';
import 'package:isar/isar.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/db_service.dart';
import '../../models/song.dart';
import '../../models/playlist.dart';
import '../../widgets/song_option_widgets.dart';
import '../../widgets/playlist_cover_widget.dart';
import '../player/now_playing_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import './liked_songs_screen.dart';
import './metadata_editor_screen.dart';
import '../../services/metadata_service.dart';

// Filter state
enum LibraryFilter { all, playlists, artists, albums }
final libraryFilterProvider = StateProvider<LibraryFilter>((ref) => LibraryFilter.all);
final librarySelectionProvider = StateProvider<Set<int>>((ref) => {});
final libraryPlaylistSelectionProvider = StateProvider<Set<int>>((ref) => {});
final selectionActiveProvider = StateProvider<bool>((ref) => false);
final playlistSelectionActiveProvider = StateProvider<bool>((ref) => false);

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final likedSongs = ref.watch(likedSongsProvider);
    final allSongs = ref.watch(allSongsProvider);
    final filter = ref.watch(libraryFilterProvider);
    final selection = ref.watch(librarySelectionProvider);
    final playlistSelection = ref.watch(libraryPlaylistSelectionProvider);
    final inSelectionMode = ref.watch(selectionActiveProvider) || selection.isNotEmpty;
    final inPlaylistSelectionMode = ref.watch(playlistSelectionActiveProvider) || playlistSelection.isNotEmpty;

    return PrimaryScrollController(
      controller: _scrollController,
      child: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 6.0,
        radius: const Radius.circular(6),
        thumbColor: BopTheme.green.withOpacity(0.6),
        interactive: true,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.top + 8)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                // ── Header + selection actions ──────
                if (inSelectionMode && filter != LibraryFilter.playlists)
                  _SelectionHeader(
                    count: selection.length,
                    onClear: () {
                      ref.read(librarySelectionProvider.notifier).state = {};
                      ref.read(selectionActiveProvider.notifier).state = false;
                    },
                    onAutoFill: () => _showBulkAutoFillDialog(context, ref, selection.toList()),
                    onAddToPlaylist: () => _showMultiPlaylistSelector(context, ref, selection.toList()),
                    onDelete: () async {
                      final confirm = await _showBulkRemoveDialog(context, selection.length);
                      if (confirm == true) {
                        final ids = selection.toList();
                        for (final id in ids) {
                          await DbService.instance.hideSong(id);
                          ref.read(playerProvider.notifier).removeSong(id);
                        }
                        ref.read(librarySelectionProvider.notifier).state = {};
                        ref.invalidate(allSongsProvider);
                        ref.invalidate(likedSongsProvider);
                        ref.invalidate(recentSongsProvider);
                      }
                    },
                  )
                else if (inPlaylistSelectionMode && filter == LibraryFilter.playlists)
                  _SelectionHeader(
                    count: playlistSelection.length,
                    onClear: () {
                      ref.read(libraryPlaylistSelectionProvider.notifier).state = {};
                      ref.read(playlistSelectionActiveProvider.notifier).state = false;
                    },
                    onDelete: () async {
                      final confirm = await _showBulkRemoveDialog(context, playlistSelection.length, isPlaylist: true);
                      if (confirm == true) {
                        for (final id in playlistSelection) {
                          await DbService.instance.deletePlaylist(id);
                        }
                        ref.read(libraryPlaylistSelectionProvider.notifier).state = {};
                      }
                    },
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your Library',
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, color: BopTheme.textSecondary),
                            tooltip: 'Create Playlist',
                            onPressed: () => _showCreatePlaylistDialog(context),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_note, color: BopTheme.textSecondary),
                            tooltip: 'Bulk Genre Management',
                            onPressed: () => _showBulkGenreEditor(context, ref),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: BopTheme.textSecondary),
                            tooltip: 'Edit / Select',
                            onPressed: () {
                              if (ref.read(libraryFilterProvider) == LibraryFilter.playlists) {
                                ref.read(playlistSelectionActiveProvider.notifier).state = true;
                              } else {
                                ref.read(selectionActiveProvider.notifier).state = true;
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: BopTheme.textSecondary),
                            tooltip: 'Rescan Device',
                            onPressed: () => _showRescanDialog(context, ref),
                          ),
                        ],
                      ),
                    ],
                  ),

                // ── Filter chips ──────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _FilterChip(
                        'All Songs',
                        filter == LibraryFilter.all,
                        () {
                          ref.read(libraryFilterProvider.notifier).state = LibraryFilter.all;
                          ref.read(librarySelectionProvider.notifier).state = {};
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        'Playlists',
                        filter == LibraryFilter.playlists,
                        () {
                          ref.read(libraryFilterProvider.notifier).state = LibraryFilter.playlists;
                          ref.read(librarySelectionProvider.notifier).state = {};
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        'Artists',
                        filter == LibraryFilter.artists,
                        () {
                          ref.read(libraryFilterProvider.notifier).state = LibraryFilter.artists;
                          ref.read(librarySelectionProvider.notifier).state = {};
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        'Albums',
                        filter == LibraryFilter.albums,
                        () {
                          ref.read(libraryFilterProvider.notifier).state = LibraryFilter.albums;
                          ref.read(librarySelectionProvider.notifier).state = {};
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Liked Songs shortcut ──────────────
                likedSongs.when(
                  data: (songs) => _LikedSongsTile(
                    count: songs.length,
                    onTap: () {
                      if (songs.isNotEmpty) {
                        ref.read(playerProvider.notifier).playQueue(songs);
                      }
                    },
                  ),
                  loading: () => _LikedSongsTile(count: 0, onTap: () {}),
                  error: (_, __) => _LikedSongsTile(count: 0, onTap: () {}),
                ),
                const Divider(height: 1, color: Colors.white10),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // ── All Songs / Playlists list (lazy) ──────────
        if (filter == LibraryFilter.playlists)
          ref.watch(playlistsStreamProvider).when(
            data: (list) => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final p = list[i];
                  final isSelected = playlistSelection.contains(p.id);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: PlaylistCoverWidget(playlist: p, size: 52),
                    title: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Playlist • ${p.songs.length} songs', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
                    trailing: inPlaylistSelectionMode
                        ? Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? BopTheme.green : BopTheme.textSecondary,
                            size: 24,
                          )
                        : const Icon(Icons.chevron_right, color: BopTheme.textSecondary),
                    onTap: () {
                      if (inPlaylistSelectionMode) {
                        final newSelection = Set<int>.from(playlistSelection);
                        if (isSelected) newSelection.remove(p.id);
                        else newSelection.add(p.id);
                        ref.read(libraryPlaylistSelectionProvider.notifier).state = newSelection;
                      } else {
                        showPlaylistDetails(context, ref, p);
                      }
                    },
                    onLongPress: () {
                      if (!inPlaylistSelectionMode) {
                        ref.read(playlistSelectionActiveProvider.notifier).state = true;
                        ref.read(libraryPlaylistSelectionProvider.notifier).state = {p.id};
                      }
                    },
                  );
                },
                childCount: list.length,
              ),
            ),
            loading: () => const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SliverToBoxAdapter(
              child: Text('Error loading playlists', style: TextStyle(color: Colors.red)),
            ),
          )
        else
          allSongs.when(
            data: (songs) {
              if (songs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No songs found.\nScan your device from the home screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: BopTheme.textMuted),
                      ),
                    ),
                  ),
                );
              }

              if (filter == LibraryFilter.artists) {
                final artistMapping = <String, List<Song>>{};
                for (final s in songs) {
                  artistMapping.putIfAbsent(s.artist, () => []).add(s);
                }
                final artistsList = artistMapping.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                  
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: artistsList.length,
                    itemBuilder: (_, i) {
                      final artist = artistsList[i].key;
                      final artistSongs = artistsList[i].value;
                      final artSong = artistSongs.cast<Song?>().firstWhere(
                        (s) => s!.artBytes != null && s.artBytes!.isNotEmpty,
                        orElse: () => null,
                      );
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: BopTheme.surfaceAlt,
                              image: artSong?.artBytes != null && artSong!.artBytes!.isNotEmpty
                                ? DecorationImage(
                                    image: ResizeImage(MemoryImage(Uint8List.fromList(artSong.artBytes!)), width: 100, height: 100), 
                                    fit: BoxFit.cover
                                  )
                                : null,
                            ),
                            child: artSong?.artBytes == null || artSong!.artBytes!.isEmpty
                              ? const Icon(Icons.person, color: Colors.white54)
                              : null,
                          ),
                          title: Text(artist, style: const TextStyle(color: Colors.white)),
                          subtitle: Text('${artistSongs.length} songs', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistName: artist)));
                          },
                        ),
                      );
                    },
                  ),
                );
              }

              if (filter == LibraryFilter.albums) {
                final albumMapping = <String, List<Song>>{};
                for (final s in songs) {
                  albumMapping.putIfAbsent(s.album, () => []).add(s);
                }
                final albumsList = albumMapping.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                  
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: albumsList.length,
                    itemBuilder: (_, i) {
                      final album = albumsList[i].key;
                      final albumSongs = albumsList[i].value;
                      final artist = albumSongs.first.artist;
                      final artSong = albumSongs.cast<Song?>().firstWhere(
                        (s) => s!.artBytes != null && s.artBytes!.isNotEmpty,
                        orElse: () => null,
                      );
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: BopTheme.surfaceAlt,
                              image: artSong?.artBytes != null && artSong!.artBytes!.isNotEmpty
                                ? DecorationImage(
                                    image: ResizeImage(MemoryImage(Uint8List.fromList(artSong.artBytes!)), width: 100, height: 100), 
                                    fit: BoxFit.cover
                                  )
                                : null,
                            ),
                            child: artSong?.artBytes == null || artSong!.artBytes!.isEmpty
                              ? const Icon(Icons.album, color: Colors.white54)
                              : null,
                          ),
                          title: Text(album, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumName: album, artist: artist)));
                          },
                        ),
                      );
                    },
                  ),
                );
              }

              final filteredSongs = songs;

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: filteredSongs.length,
                  itemBuilder: (_, i) {
                    final song = filteredSongs[i];
                    final isSelected = selection.contains(song.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SongTile(
                        song: song,
                        isSelected: isSelected,
                        inSelectionMode: inSelectionMode,
                        onTap: () {
                          if (inSelectionMode) {
                            final newSet = Set<int>.from(selection);
                            if (isSelected) {
                              newSet.remove(song.id);
                            } else {
                              newSet.add(song.id);
                            }
                            ref.read(librarySelectionProvider.notifier).state = newSet;
                          } else {
                            ref.read(playerProvider.notifier).playQueue(
                              filteredSongs,
                              startIndex: i,
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NowPlayingScreen(song: song),
                              ),
                            );
                          }
                        },
                        onLongPress: () {
                          if (!inSelectionMode) {
                            ref.read(selectionActiveProvider.notifier).state = true;
                            ref.read(librarySelectionProvider.notifier).state = {song.id};
                          }
                        },
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(
              child: Text('Error loading library'),
            ),
          ),
      ],
        ),
      ),
    );
  }
}


class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? BopTheme.green : BopTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? Colors.black : BopTheme.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            )),
      ),
    );
  }
}

class _LikedSongsTile extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _LikedSongsTile({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A0070), BopTheme.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.favorite, color: Colors.white, size: 20),
      ),
      title: const Text('Liked Songs',
          style: TextStyle(
              color: BopTheme.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text('$count songs',
          style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right,
          color: BopTheme.textSecondary),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
        );
      },
    );
  }
}

class _SongTile extends ConsumerWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool inSelectionMode;

  const _SongTile({
    required this.song,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
    this.inSelectionMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? BopTheme.green.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        onTap: onTap,
        onLongPress: onLongPress,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 44,
          height: 44,
          child: song.artBytes != null && song.artBytes!.isNotEmpty
              ? Image.memory(
                  Uint8List.fromList(song.artBytes!),
                  key: ValueKey('lib_art_${song.id}'),
                  cacheWidth: 88,
                  cacheHeight: 88,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              : Container(
                  color: const Color(0xFFC0392B),
                  child: Center(
                    child: Text(
                      song.title.isNotEmpty ? song.title[0] : '♪',
                      style: const TextStyle(
                        color: Color(0xFFF1C40F),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
        ),
      ),
      title: Text(song.title,
          style: const TextStyle(
              color: BopTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist,
          style: const TextStyle(
              color: BopTheme.textSecondary, fontSize: 11)),
      trailing: inSelectionMode
          ? Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? BopTheme.green : BopTheme.textSecondary,
              size: 20,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(song.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: song.isLiked
                          ? BopTheme.green
                          : BopTheme.textSecondary,
                      size: 20),
                  onPressed: () async {
                    await DbService.instance.toggleLike(song.id);
                    ref.invalidate(likedSongsProvider);
                    ref.invalidate(allSongsProvider);
                    ref.read(playerProvider.notifier).refreshCurrentSong();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: BopTheme.textSecondary, size: 20),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: const Color(0xFF282828),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => _LibrarySongMenu(song: song),
                    );
                  },
                ),
              ],
            ),
      ),
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onAutoFill;

  const _SelectionHeader({
    required this.count,
    required this.onClear,
    required this.onDelete,
    this.onAddToPlaylist,
    this.onAutoFill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClear,
          ),
          const SizedBox(width: 8),
          Text('$count selected',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (onAutoFill != null)
            IconButton(
              icon: const Icon(Icons.auto_fix_high, color: BopTheme.green),
              tooltip: 'Auto-fill Metadata',
              onPressed: onAutoFill,
            ),
          if (onAddToPlaylist != null)
            IconButton(
              icon: const Icon(Icons.playlist_add, color: Colors.white),
              tooltip: 'Add to Playlist',
              onPressed: onAddToPlaylist,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: BopTheme.red),
            tooltip: 'Remove',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

Future<bool?> _showBulkRemoveDialog(BuildContext context, int count, {bool isPlaylist = false}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: Text('Remove $count ${isPlaylist ? 'Playlists' : 'Songs'}?', style: const TextStyle(color: Colors.white)),
      content: Text(
          isPlaylist 
              ? 'This will permanently delete the selected playlists from your library.'
              : 'This will hide these songs from your library. They will NOT be re-scanned unless you reset your database.',
          style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(isPlaylist ? 'Delete' : 'Hide', style: TextStyle(color: isPlaylist ? BopTheme.red : BopTheme.green)),
        ),
      ],
    ),
  );
}

Future<void> _showBulkAutoFillDialog(BuildContext context, WidgetRef ref, List<int> songIds) async {
  final List<Song> selectedSongs = [];
  for (final id in songIds) {
    final s = await DbService.instance.songs.get(id);
    if (s != null) selectedSongs.add(s);
  }

  if (context.mounted && selectedSongs.isNotEmpty) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MetadataEditorScreen(songs: selectedSongs),
      ),
    );
  }
}

Future<void> _showMultiPlaylistSelector(BuildContext context, WidgetRef ref, List<int> songIds) async {
  final List<Song> selectedSongs = [];
  for (final id in songIds) {
    final s = await DbService.instance.songs.get(id);
    if (s != null) selectedSongs.add(s);
  }

  if (context.mounted && selectedSongs.isNotEmpty) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlaylistSelector.multiple(songs: selectedSongs),
    );
  }
}

class _LibrarySongMenu extends ConsumerWidget {
  final Song song;
  const _LibrarySongMenu({required this.song});

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
                    child: song.artBytes != null
                        ? Image.memory(
                            Uint8List.fromList(song.artBytes!),
                            fit: BoxFit.cover,
                            cacheWidth: 88,
                            cacheHeight: 88,
                          )
                        : const ColoredBox(color: Color(0xFFC0392B)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(song.artist,
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
          ListTile(
            leading: Icon(
                song.isLiked ? Icons.favorite : Icons.favorite_border,
                color: song.isLiked ? BopTheme.green : BopTheme.textSecondary,
                size: 20),
            title: Text(song.isLiked ? 'Unlike' : 'Like',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () async {
              Navigator.pop(context);
              await DbService.instance.toggleLike(song.id);
              ref.invalidate(likedSongsProvider);
              ref.invalidate(allSongsProvider);
              ref.read(playerProvider.notifier).refreshCurrentSong();
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: BopTheme.textSecondary, size: 20),
            title: const Text('Add to playlist', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              _showPlaylistSelector(context, ref, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music, color: BopTheme.textSecondary, size: 20),
            title: const Text('Add to queue', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              ref.read(playerProvider.notifier).addToQueue(song);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to queue')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.share, color: BopTheme.textSecondary, size: 20),
            title: const Text('Share', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              Share.share('Check out this song: ${song.title} by ${song.artist}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: BopTheme.textSecondary, size: 20),
            title: const Text('Edit info', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MetadataEditorScreen(songs: [song]),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.album_outlined, color: BopTheme.textSecondary, size: 20),
            title: const Text('View album', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlbumScreen(albumName: song.album, artist: song.artist),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: BopTheme.textSecondary, size: 20),
            title: const Text('Song credits', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              _showCreditsDialog(context, song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.hide_source, color: BopTheme.red, size: 20),
            title: const Text('Hide from library', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('Song will stay on device but won\'t show here.', style: TextStyle(color: Colors.white38, fontSize: 10)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF282828),
                  title: const Text('Hide Song', style: TextStyle(color: Colors.white)),
                  content: Text('Hide "${song.title}" from your library? It will not be scanned again unless you reset your database.',
                      style: const TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hide', style: TextStyle(color: BopTheme.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await DbService.instance.hideSong(song.id);
                if (context.mounted) {
                  ref.read(playerProvider.notifier).removeSong(song.id);
                  ref.invalidate(allSongsProvider);
                  ref.invalidate(likedSongsProvider);
                  ref.invalidate(recentSongsProvider);
                }
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.white38, size: 20),
            title: const Text('Delete from device', style: TextStyle(color: Colors.white38, fontSize: 14)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF282828),
                  title: const Text('Delete Permanently', style: TextStyle(color: Colors.white)),
                  content: Text('This will delete "${song.title}" PERMANENTLY from your phone storage. This cannot be undone.',
                      style: const TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete', style: TextStyle(color: BopTheme.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                try {
                  final f = File(song.filePath);
                  if (f.existsSync()) f.deleteSync();
                } catch (_) {}
                await DbService.instance.deleteSong(song.id);
                if (context.mounted) {
                  ref.read(playerProvider.notifier).removeSong(song.id);
                  ref.invalidate(allSongsProvider);
                  ref.invalidate(likedSongsProvider);
                  ref.invalidate(recentSongsProvider);
                }
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

void _showPlaylistSelector(BuildContext context, WidgetRef ref, Song song) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF282828),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => PlaylistSelector(song: song),
  );
}

void _showCreatePlaylistDialog(BuildContext context) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: Colors.white38),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              await DbService.instance.createPlaylist(name);
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          child: const Text('Create', style: TextStyle(color: BopTheme.green)),
        ),
      ],
    ),
  );
}

void _showRescanDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      bool started = false;
      int current = 0;
      int total = 0;
      bool done = false;

      return StatefulBuilder(builder: (context, setDialogState) {
        if (!started) {
          started = true;
          ScannerService.instance.scanAndSave(
            onProgress: (c, t) {
              if (ctx.mounted) {
                setDialogState(() {
                  current = c;
                  total = t;
                  if (t > 0 && c >= t) done = true;
                });
              }
            },
          ).then((_) {
            if (ctx.mounted) {
              setDialogState(() => done = true);
              ref.invalidate(allSongsProvider);
              ref.invalidate(recentSongsProvider);
              ref.invalidate(likedSongsProvider);
            }
          });
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Scanning Library', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (total > 0) ...[
                LinearProgressIndicator(
                  value: total == 0 ? 0 : current / total,
                  backgroundColor: Colors.white24,
                  color: BopTheme.green,
                ),
                const SizedBox(height: 16),
                Text('$current / $total scanned', style: const TextStyle(color: Colors.white70)),
              ] else if (done) ...[
                const Text('Library is up to date!', style: TextStyle(color: Colors.white70)),
              ] else ...[
                const CircularProgressIndicator(color: BopTheme.green),
                const SizedBox(height: 16),
                const Text('Looking for new files...', style: TextStyle(color: Colors.white70)),
              ],
            ],
          ),
          actions: [
            if (done || total == 0)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: BopTheme.green)),
              ),
          ],
        );
      });
    },
  );
}

void showPlaylistDetails(BuildContext context, WidgetRef ref, Playlist playlist) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlaylistScreen(playlist: playlist),
    ),
  );
}

void _confirmDeletePlaylist(BuildContext context, WidgetRef ref, Playlist playlist) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white)),
      content: Text('Are you sure you want to delete "${playlist.name}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await DbService.instance.deletePlaylist(playlist.id);
          },
          child: const Text('Delete', style: TextStyle(color: BopTheme.red)),
        ),
      ],
    ),
  );
}

void _showBulkGenreEditor(BuildContext context, WidgetRef ref) async {
  final songs = await DbService.instance.songs.where().findAll();
  final genreSet = <String>{};
  for (final s in songs) {
    if (s.genre.isNotEmpty) {
      final parts = s.genre.split(RegExp(r'[,/]')).map((g) => g.trim());
      for (final p in parts) {
        if (p.isNotEmpty) genreSet.add(p);
      }
    }
  }
  final genres = genreSet.toList()..sort();

  if (context.mounted) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF191414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GenreEditorModal(genres: genres),
    ).then((_) {
      ref.invalidate(allSongsProvider);
    });
  }
}

class _GenreEditorModal extends StatefulWidget {
  final List<String> genres;
  const _GenreEditorModal({required this.genres});

  @override
  State<_GenreEditorModal> createState() => _GenreEditorModalState();
}

class _GenreEditorModalState extends State<_GenreEditorModal> {
  late List<String> _genres;

  @override
  void initState() {
    super.initState();
    _genres = List.from(widget.genres);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Manage Genres', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Text('Tap edit to rename · tap eye to view & edit songs.', style: TextStyle(color: BopTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: _genres.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10),
              itemBuilder: (context, i) {
                final genre = _genres[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.label_outline, color: BopTheme.green),
                  title: Text(genre, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, color: Colors.white24, size: 18),
                        onPressed: () => _viewGenreSongs(context, genre),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white24, size: 18),
                        onPressed: () => _renameGenre(context, genre),
                      ),
                    ],
                  ),
                  onTap: () => _renameGenre(context, genre),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _viewGenreSongs(BuildContext context, String genre) async {
    final isar = DbService.instance.isar;
    final allSongs = await isar.songs.where().findAll();
    final genreSongs = allSongs.where((s) {
      if (s.genre.isEmpty) return false;
      return s.genre.split(RegExp(r'[,/]')).map((g) => g.trim().toLowerCase()).contains(genre.toLowerCase());
    }).toList();

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _GenreSongsViewerScreen(genre: genre, songs: genreSongs),
        ),
      );
    }
  }

  void _renameGenre(BuildContext context, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: Text('Rename "$oldName"', style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'New genre name',
            hintStyle: TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: BopTheme.green)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary))),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                Navigator.pop(ctx);
                await _performRename(oldName, newName);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename', style: TextStyle(color: BopTheme.green, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRename(String oldName, String newName) async {
    final isar = DbService.instance.isar;
    final songs = await isar.songs.where().findAll();
    
    await isar.writeTxn(() async {
      for (final s in songs) {
        if (s.genre.isEmpty) continue;
        
        final parts = s.genre.split(RegExp(r'[,/]')).map((g) => g.trim()).toList();
        bool changed = false;
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].toLowerCase() == oldName.toLowerCase()) {
            parts[i] = newName;
            changed = true;
          }
        }
        
        if (changed) {
          s.genre = parts.join(', ');
          await isar.songs.put(s);
        }
      }
    });

    if (mounted) {
      setState(() {
        final idx = _genres.indexOf(oldName);
        if (idx != -1) _genres[idx] = newName;
        _genres.sort();
      });
    }
  }
}

void _showCreditsDialog(BuildContext context, Song song) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF282828),
      title: const Text('Song Credits', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Title: ${song.title}', style: const TextStyle(color: Colors.white70)),
          Text('Artist: ${song.artist}', style: const TextStyle(color: Colors.white70)),
          Text('Album: ${song.album}', style: const TextStyle(color: Colors.white70)),
          if (song.genre.isNotEmpty)
            Text('Genre: ${song.genre}', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          const Text('Source: Local File', style: TextStyle(color: BopTheme.textMuted, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close', style: TextStyle(color: BopTheme.green)),
        ),
      ],
    ),
  );
}

// ── Genre Songs Viewer ─────────────────────────────────────────────────────────
class _GenreSongsViewerScreen extends StatefulWidget {
  final String genre;
  final List<Song> songs;
  const _GenreSongsViewerScreen({required this.genre, required this.songs});

  @override
  State<_GenreSongsViewerScreen> createState() => _GenreSongsViewerScreenState();
}

class _GenreSongsViewerScreenState extends State<_GenreSongsViewerScreen> {
  final Set<int> _selected = {};
  bool _selectionMode = false;
  late List<Song> _songs;

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.songs);
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterSelection(int id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _editSingle(Song song) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => MetadataEditorScreen(songs: [song])));
  }

  void _editSelected() {
    final toEdit = _songs.where((s) => _selected.contains(s.id)).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => MetadataEditorScreen(songs: toEdit)));
  }

  Future<void> _removeFromLibrary(Song song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Remove from Library?', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${song.title}" will be removed from your library. The file won\'t be deleted.',
          style: const TextStyle(color: BopTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await DbService.instance.isar.writeTxn(() => DbService.instance.isar.songs.delete(song.id));
      setState(() {
        _songs.removeWhere((s) => s.id == song.id);
        _selected.remove(song.id);
        if (_selected.isEmpty) _selectionMode = false;
      });
    }
  }

  Future<void> _removeSelectedFromLibrary() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Remove from Library?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove $count song${count == 1 ? '' : 's'} from your library? Files won\'t be deleted.',
          style: const TextStyle(color: BopTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final ids = _selected.toList();
      await DbService.instance.isar.writeTxn(() => DbService.instance.isar.songs.deleteAll(ids));
      setState(() {
        _songs.removeWhere((s) => ids.contains(s.id));
        _selected.clear();
        _selectionMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BopTheme.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() { _selected.clear(); _selectionMode = false; }),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        title: _selectionMode
            ? Text('${_selected.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.genre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                  Text('${_songs.length} songs', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12)),
                ],
              ),
        actions: [
          if (_selectionMode) ...[
            TextButton.icon(
              onPressed: () => setState(() {
                if (_selected.length == _songs.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(_songs.map((s) => s.id));
                }
              }),
              icon: Icon(
                _selected.length == _songs.length ? Icons.deselect : Icons.select_all,
                color: BopTheme.green, size: 18,
              ),
              label: Text(
                _selected.length == _songs.length ? 'Deselect' : 'All',
                style: const TextStyle(color: BopTheme.green),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_note, color: BopTheme.green),
              tooltip: 'Edit selected',
              onPressed: _selected.isEmpty ? null : _editSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Remove from library',
              onPressed: _selected.isEmpty ? null : _removeSelectedFromLibrary,
            ),
          ],
        ],
      ),
      body: _songs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_off, color: BopTheme.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text('No songs tagged as "${widget.genre}"',
                      style: const TextStyle(color: BopTheme.textMuted, fontSize: 14)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _songs.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
              itemBuilder: (context, i) {
                final song = _songs[i];
                final isSelected = _selected.contains(song.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(song.id);
                    } else {
                      _editSingle(song);
                    }
                  },
                  onLongPress: () {
                    if (!_selectionMode) _enterSelection(song.id);
                  },
                  leading: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: song.artBytes != null && song.artBytes!.isNotEmpty
                              ? Image.memory(Uint8List.fromList(song.artBytes!), fit: BoxFit.cover, gaplessPlayback: true)
                              : Container(color: BopTheme.surfaceAlt, child: const Icon(Icons.music_note, color: Colors.white24, size: 22)),
                        ),
                      ),
                      if (isSelected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: BopTheme.green.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 20),
                          ),
                        ),
                    ],
                  ),
                  title: Text(song.title,
                      style: TextStyle(
                          color: isSelected ? BopTheme.green : Colors.white,
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(song.artist,
                      style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: _selectionMode
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_note, color: BopTheme.textMuted, size: 20),
                              tooltip: 'Edit metadata',
                              onPressed: () => _editSingle(song),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              tooltip: 'Remove from library',
                              onPressed: () => _removeFromLibrary(song),
                            ),
                          ],
                        ),
                );
              },
            ),
    );
  }
}
