// widgets/song_option_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/db_service.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';

final playlistsStreamProvider = StreamProvider<List<Playlist>>((ref) {
  return DbService.instance.playlists.where().watch(fireImmediately: true);
});

class PlaylistSelector extends ConsumerWidget {
  final List<Song> songs;
  PlaylistSelector({super.key, required Song song}) : songs = [song];
  const PlaylistSelector.multiple({super.key, required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsStreamProvider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(songs.length > 1 ? 'Add ${songs.length} songs to...' : 'Add to Playlist',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.add, color: BopTheme.green),
            title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
            onTap: () => _showCreatePlaylistDialog(context),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: playlists.when(
              data: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final p = list[index];
                  return ListTile(
                    leading: const Icon(Icons.playlist_play, color: BopTheme.textSecondary),
                    title: Text(p.name, style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      for (final song in songs) {
                        await DbService.instance.addSongToPlaylist(p.id, song.id);
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to ${p.name}')),
                      );
                    },
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Error loading playlists', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'My Playlist #1',
            hintStyle: TextStyle(color: Colors.white30),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await DbService.instance.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create', style: TextStyle(color: BopTheme.green)),
          ),
        ],
      ),
    );
  }
}

class SleepTimerSelector extends ConsumerWidget {
  const SleepTimerSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final times = [
      (0, 'Off'),
      (5, '5 Minutes'),
      (15, '15 Minutes'),
      (30, '30 Minutes'),
      (60, '1 Hour'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sleep Timer',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ...times.map((t) => ListTile(
              title: Text(t.$2, style: const TextStyle(color: Colors.white)),
              onTap: () {
                ref.read(playerProvider.notifier).setSleepTimer(t.$1);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.$1 == 0 ? 'Sleep timer off' : 'Timer set for ${t.$2}')),
                );
              },
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}
