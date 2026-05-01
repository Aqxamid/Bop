// screens/library/search_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/stats_provider.dart';
import '../../providers/player_provider.dart';
import '../../models/song.dart';
import '../player/now_playing_screen.dart';
import '../../services/db_service.dart';
import 'metadata_editor_screen.dart';
import 'library_screen.dart';
import '../../widgets/song_option_widgets.dart';

// ── Genre color palette ────────────────────────────────────────
const _genreColors = <String, Color>{
  'Pop':       Color(0xFF8C67AC),
  'Indie':     Color(0xFF608B4E),
  'K-Pop':     Color(0xFFE74C3C),
  'R&B':       Color(0xFFE8821A),
  'Hip-Hop':   Color(0xFF2C3E50),
  'Rock':      Color(0xFFA83232),
  'Jazz':      Color(0xFF2D6A4F),
  'Classical': Color(0xFF5C4A1E),
  'Metal':     Color(0xFF1A1A2E),
  'Electronic':Color(0xFF0E4D64),
  'Country':   Color(0xFF856B3B),
  'Latin':     Color(0xFFC0392B),
  'Reggae':    Color(0xFF1A5632),
  'Soul':      Color(0xFF6B3FA0),
  'Blues':     Color(0xFF1A3A5C),
  'Punk':      Color(0xFF922B21),
  'Folk':      Color(0xFF6E5B3A),
  'Dance':     Color(0xFF1DB954),
  'Ambient':   Color(0xFF2E4057),
  'Gospel':    Color(0xFF7D3C98),
  'OPM':       Color(0xFF1F618D),
  'Alternative': Color(0xFF5D6D7E),
  'Acoustic':  Color(0xFF6E2C00),
  'Lo-fi':     Color(0xFF2E4053),
  'Rap':       Color(0xFF641E16),
  'Disco':     Color(0xFFD4AC0D),
  'Funk':      Color(0xFFE67E22),
  'Grunge':    Color(0xFF515A5A),
  'Trap':      Color(0xFF4A235A),
  'House':     Color(0xFF117A65),
  'Techno':    Color(0xFF1B2631),
};

Color _colorForGenre(String genre) {
  if (_genreColors.containsKey(genre)) return _genreColors[genre]!;
  for (final entry in _genreColors.entries) {
    if (entry.key.toLowerCase() == genre.toLowerCase()) return entry.value;
  }
  final hash = genre.hashCode.abs();
  return HSLColor.fromAHSL(1.0, (hash % 360).toDouble(), 0.5, 0.3).toColor();
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSongs = ref.watch(allSongsProvider);
    final selectedGenre = ref.watch(searchGenreProvider);

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
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 120),
          children: [

        const Text('Search',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),

        // ── Search bar ────────────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.black54, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.black, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Artists, songs, or albums',
                    hintStyle: TextStyle(color: Colors.black45, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) {
                    setState(() => _query = v);
                    if (v.isNotEmpty) ref.read(searchGenreProvider.notifier).state = null;
                  },
                ),
              ),
              if (_query.isNotEmpty)
                InkWell(
                  onTap: () {
                    _controller.clear();
                    setState(() => _query = '');
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close, color: Colors.black54, size: 16),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Genre view ────────────────────────
        if (_query.isEmpty) ...[
          if (selectedGenre != null) ...[
            // ── Genre Detail ──
            Row(
              children: [
                InkWell(
                  onTap: () => ref.read(searchGenreProvider.notifier).state = null,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, color: BopTheme.textPrimary, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Text(selectedGenre,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            allSongs.when(
              data: (songs) {
                final genreSongs = songs.where((s) {
                  final genres = s.genre.split(RegExp(r'[,/]')).map((g) => g.trim().toLowerCase());
                  return genres.contains(selectedGenre.toLowerCase());
                }).toList();
                if (genreSongs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No songs in this genre', style: TextStyle(color: BopTheme.textMuted)),
                  );
                }
                return Column(
                  children: genreSongs.asMap().entries.map((entry) {
                    final song = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: song.artBytes != null && song.artBytes!.isNotEmpty
                              ? Image.memory(
                                  Uint8List.fromList(song.artBytes!),
                                  key: ValueKey('genre_art_${song.id}'),
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Container(
                                  color: _colorForGenre(selectedGenre),
                                  child: const Center(
                                    child: Icon(Icons.music_note, color: Colors.white54, size: 18),
                                  ),
                                ),
                        ),
                      ),
                      title: Text(song.title,
                          style: const TextStyle(color: BopTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert, color: BopTheme.textSecondary, size: 20),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: const Color(0xFF282828),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (_) => _SearchSongMenu(song: song),
                          );
                        },
                      ),
                      onTap: () {
                        ref.read(playerProvider.notifier).playQueue(genreSongs, startIndex: entry.key);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
                      },
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Error loading songs'),
            ),
          ] else ...[
            // ── Genre Grid ──
            const Text('Browse categories',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            allSongs.when(
              data: (songs) {
                final genreMap = <String, List<Song>>{};
                for (final song in songs) {
                  final rawGenre = song.genre.trim();
                  if (rawGenre.isEmpty || rawGenre == 'Unknown') continue;
                  final parts = rawGenre.split(RegExp(r'[,/]')).map((g) {
                    final t = g.trim();
                    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1).toLowerCase();
                  }).where((g) => g.isNotEmpty);
                  for (final genre in parts) {
                    genreMap.putIfAbsent(genre, () => []).add(song);
                  }
                }
                final sortedGenres = genreMap.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
                if (sortedGenres.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No genres found.\nEdit metadata to see categories.',
                        textAlign: TextAlign.center, style: TextStyle(color: BopTheme.textMuted)),
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.7,
                  ),
                  itemCount: sortedGenres.length,
                  itemBuilder: (context, index) {
                    final genre = sortedGenres[index].key;
                    final gSongs = sortedGenres[index].value;
                    final artSong = gSongs.cast<Song?>().firstWhere(
                          (s) => s!.artBytes != null && s.artBytes!.isNotEmpty,
                          orElse: () => null,
                        );
                    return _GenreCard(
                      name: genre,
                      color: _colorForGenre(genre),
                      artSong: artSong,
                      songCount: gSongs.length,
                      onTap: () => ref.read(searchGenreProvider.notifier).state = genre,
                    );
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const Text('Error'),
            ),
          ],
        ],

        // ── Search results ────────────────────
        if (_query.isNotEmpty)
          allSongs.when(
            data: (songs) {
              final q = _query.toLowerCase().trim();
              final terms = q.split(RegExp(r'\s+'));
              final results = songs.where((s) {
                final matchString = '${s.title} ${s.artist} ${s.album} ${s.genre}'.toLowerCase();
                return terms.every((t) => matchString.contains(t));
              }).toList();
              return _SearchResults(
                query: _query,
                results: results,
                onTap: (song, index) {
                  ref.read(playerProvider.notifier).playQueue(results, startIndex: index);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Text('Error'),
          ),
      ],
        ),
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String name;
  final Color color;
  final Song? artSong;
  final int songCount;
  final VoidCallback onTap;

  const _GenreCard({required this.name, required this.color, this.artSong, required this.songCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('$songCount songs', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                ],
              ),
            ),
            if (artSong != null && artSong!.artBytes != null && artSong!.artBytes!.isNotEmpty)
              Positioned(
                right: -8,
                bottom: -8,
                child: Transform.rotate(
                  angle: 0.35,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(-2, 2))],
                      image: DecorationImage(image: MemoryImage(Uint8List.fromList(artSong!.artBytes!)), fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final String query;
  final List<Song> results;
  final void Function(Song song, int index) onTap;
  const _SearchResults({required this.query, required this.results, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Results for "$query"', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (results.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No local songs found', style: TextStyle(color: BopTheme.textMuted))))
        else
          ...results.asMap().entries.map((entry) {
            final song = entry.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: song.artBytes != null && song.artBytes!.isNotEmpty
                      ? Image.memory(Uint8List.fromList(song.artBytes!), key: ValueKey('search_art_${song.id}'), fit: BoxFit.cover, gaplessPlayback: true)
                      : Container(color: BopTheme.surfaceAlt, child: const Center(child: Icon(Icons.music_note, color: Colors.white54, size: 18))),
                ),
              ),
              title: Text(song.title, style: const TextStyle(color: BopTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
              onTap: () => onTap(song, entry.key),
            );
          }),
      ],
    );
  }
}

class _SearchSongMenu extends ConsumerWidget {
  final Song song;
  const _SearchSongMenu({required this.song});

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
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: const Color(0xFF1E1E1E),
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to queue')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note, color: BopTheme.textSecondary, size: 20),
            title: const Text('Edit metadata', style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => MetadataEditorScreen(songs: [song])));
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
