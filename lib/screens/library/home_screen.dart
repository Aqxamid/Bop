// screens/library/home_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/stats_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/song.dart';
import '../../widgets/playlist_collage.dart';
import '../player/now_playing_screen.dart';
import './playlist_screen.dart';
import '../../widgets/song_option_widgets.dart'; // For playlistsStreamProvider
import '../profile/settings_screen.dart';
import '../../models/playlist.dart';
import '../../services/llm_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentSongs = ref.watch(recentSongsProvider);
    
    // Greeting based on time
    final hour = DateTime.now().hour;
    String greeting = 'Good evening';
    if (hour < 12) greeting = 'Good morning';
    else if (hour < 17) greeting = 'Good afternoon';

    return ListView(
      primary: true,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 120),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              greeting,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 24),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 2),

        // ── Recently Played (2x3 Grid) ────────────
        recentSongs.when(
          data: (songs) {
            final displaySongs = songs.take(10).toList();
            if (displaySongs.isEmpty) return const SizedBox.shrink();
            return GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.4,
              ),
              itemCount: displaySongs.length,
              itemBuilder: (context, i) {
                final s = displaySongs[i];
                return InkWell(
                  onTap: () {
                    ref.read(playerProvider.notifier).playQueue(songs, startIndex: i);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: s)));
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: (s.artBytes != null && s.artBytes!.isNotEmpty)
                              ? Image.memory(
                                  Uint8List.fromList(s.artBytes!),
                                  fit: BoxFit.cover,
                                )
                              : Container(color: BopTheme.surfaceAlt),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              s.title,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24))),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),

        // ── Pick up where you left off ────────────
        const _SectionHeader(title: 'Pick up where you left off'),
        const SizedBox(height: 6),
        const _PickUpCard(),

        const SizedBox(height: 24),

        // ── Recent playlists played ─────────────────
        const _SectionHeader(title: 'Recent playlists played'),
        const SizedBox(height: 6),
        const _RecentsPlaylistsRow(),
        const SizedBox(height: 24),

        // ── AI Curated for You ──────────────────────
        Consumer(
          builder: (context, ref, _) {
            // Show 'AI Curated' only when model is actually loaded in RAM
            final isModelLoaded = ref.watch(llmModelReadyProvider);
            final isAiEnabled = ref.watch(settingsProvider.select((s) => s.aiEnabled));
            final isAiActive = isAiEnabled && isModelLoaded;
            return _SectionHeader(title: isAiActive ? 'AI Curated for You' : "Algorithm's Choice");
          },
        ),
        const SizedBox(height: 6),
        const _AiCuratedRow(),
        const SizedBox(height: 16),


        // ── Playlist Gems ───────────────────────────
        const _SectionHeader(title: "Discover Gems"),
        const SizedBox(height: 6),
        const _PlaylistGemsRow(),
        const SizedBox(height: 16),

        // ── Hidden Gems ─────────────────────────────
        const _SectionHeader(title: "Hidden Gems"),
        const SizedBox(height: 6),
        const _HiddenGemsRow(),
        const SizedBox(height: 16),

        // ── Bop Recap (Wrapped style card) ──────────
        const _BopRecapCard(),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _BopRecapCard extends ConsumerWidget {
  const _BopRecapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1DB954), Color(0xFF191414)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(Icons.auto_graph, size: 140, color: Colors.white.withOpacity(0.1)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('YOUR 2026', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                const Text('Bop Recap', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to Stats tab
                    ref.read(shellTabIndexProvider.notifier).state = 2;
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Check it out', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCuratedRow extends ConsumerWidget {
  const _AiCuratedRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(aiPlaylistsProvider);
    return playlistsAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return const Text('Start listening for AI playlists...', style: TextStyle(color: BopTheme.textMuted));
        }
        return SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final p = list[i];
              return _SmartPlaylistHorizontalItem(data: p);
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: BopTheme.green))),
      error: (_, __) => const Text('Unable to curate playlists', style: TextStyle(color: BopTheme.textMuted)),
    );
  }
}

class _PlaylistGemsRow extends ConsumerWidget {
  const _PlaylistGemsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(playlistGemsProvider);
    return songsAsync.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final s = list[i];
              return _SongHorizontalItem(song: s, queue: list, index: i);
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 120),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _HiddenGemsRow extends ConsumerWidget {
  const _HiddenGemsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(hiddenGemsProvider);
    return songsAsync.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final s = list[i];
              return _SongHorizontalItem(song: s, queue: list, index: i);
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 120),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _SongHorizontalItem extends ConsumerWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  const _SongHorizontalItem({required this.song, required this.queue, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        ref.read(playerProvider.notifier).playQueue(queue, startIndex: index);
        Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: BopTheme.surfaceAlt,
            ),
            clipBehavior: Clip.antiAlias,
            child: (song.artBytes != null && song.artBytes!.isNotEmpty)
                ? Image.memory(Uint8List.fromList(song.artBytes!), fit: BoxFit.cover)
                : const Icon(Icons.music_note, color: Colors.white24, size: 40),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: Text(song.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 120,
            child: Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _SmartPlaylistHorizontalItem extends ConsumerWidget {
  final SmartPlaylistData data;
  const _SmartPlaylistHorizontalItem({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Map SmartPlaylistData to a transient Playlist model for the screen
    final playlist = Playlist()
      ..name = data.name
      ..isAiGenerated = data.isAiGenerated
      ..createdAt = DateTime.now();
    
    // We can't use .addAll because .songs is an IsarLinks which needs an Isar session
    // But PlaylistScreen just needs a list of songs, so we will pass them via constructor or just ensure PlaylistScreen is flexible.
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistScreen(
              playlist: playlist,
              initialSongs: data.songs, // Passing songs directly
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaylistCollage(songs: data.songs, size: 120, borderRadius: 8),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: Text(data.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(data.isAiGenerated ? 'AI Curated' : 'Bop Mix', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Helper Widgets ──────────────────────────────────────────

class _PlaylistHorizontalItem extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistHorizontalItem({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(playlist: playlist)));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaylistCollage(songs: playlist.songs.toList(), size: 120, borderRadius: 8),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: Text(playlist.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text('Playlist', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
class _PickUpCard extends ConsumerWidget {
  const _PickUpCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentSongs = ref.watch(recentSongsProvider);
    return recentSongs.when(
      data: (songs) {
        if (songs.isEmpty) return const SizedBox.shrink();
        final song = songs.first;
        return InkWell(
          onTap: () {
            ref.read(playerProvider.notifier).playQueue([song]);
            Navigator.push(context, MaterialPageRoute(builder: (_) => NowPlayingScreen(song: song)));
          },
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: (song.artBytes != null && song.artBytes!.isNotEmpty)
                      ? Image.memory(
                          Uint8List.fromList(song.artBytes!),
                          fit: BoxFit.cover,
                        )
                      : Container(color: BopTheme.surfaceAlt),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(song.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(song.artist, style: const TextStyle(color: BopTheme.textSecondary, fontSize: 13)),
                        const SizedBox(height: 12),
                        const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Container(height: 140, color: BopTheme.surfaceAlt),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RecentsPlaylistsRow extends ConsumerWidget {
  const _RecentsPlaylistsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsStreamProvider);
    return SizedBox(
      height: 180,
      child: playlistsAsync.when(
        data: (list) {
          if (list.isEmpty) return const SizedBox.shrink();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final p = list[i];
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(playlist: p),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlaylistCollage(songs: p.songs.toList(), size: 120, borderRadius: 4),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 120,
                      child: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text('Playlist • ${p.songs.length} songs', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 11)),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const SizedBox(height: 120),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}
