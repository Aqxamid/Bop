// widgets/playlist_cover_widget.dart
// Spotify-style 2×2 album art collage for playlists.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/song.dart';

class PlaylistCoverWidget extends StatefulWidget {
  final Playlist playlist;
  final double size;
  final List<Song>? songs;
  const PlaylistCoverWidget({
    super.key,
    required this.playlist,
    this.size = 56,
    this.songs,
  });

  @override
  State<PlaylistCoverWidget> createState() => _PlaylistCoverWidgetState();
}

class _PlaylistCoverWidgetState extends State<PlaylistCoverWidget> {
  List<List<int>>? _cachedArts;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadArt();
  }

  @override
  void didUpdateWidget(PlaylistCoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id || oldWidget.songs != widget.songs) {
      _loadArt();
    }
  }

  Future<void> _loadArt() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      List<Song> songs;
      if (widget.songs != null && widget.songs!.isNotEmpty) {
        songs = widget.songs!;
      } else {
        if (!widget.playlist.songs.isLoaded) {
          await widget.playlist.songs.load();
        }
        songs = widget.playlist.songs.take(20).toList();
      }

      final arts = <List<int>>[];
      final seenArtHashes = <int>{};
      
      for (final song in songs) {
        if (song.artBytes != null && song.artBytes!.isNotEmpty) {
          final hash = song.artBytes!.length; 
          if (!seenArtHashes.contains(hash)) {
            seenArtHashes.add(hash);
            arts.add(song.artBytes!);
          }
          if (arts.length >= 4) break;
        }
      }
      
      if (mounted) {
        setState(() {
          _cachedArts = arts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arts = _cachedArts ?? [];
    final colorString = widget.playlist.coverColor.startsWith('#') 
        ? widget.playlist.coverColor.replaceFirst('#', '0xFF')
        : '0xFF66BB6A'; // Fallback green
    final color = Color(int.parse(colorString));

    if (arts.isEmpty) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(Icons.queue_music,
            color: Colors.white.withAlpha(153), size: widget.size * 0.45),
      );
    }

    if (arts.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          Uint8List.fromList(arts[0]),
          width: widget.size,
          height: widget.size,
          cacheWidth: (widget.size * 2).toInt(),
          cacheHeight: (widget.size * 2).toInt(),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    final half = widget.size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Column(
          children: [
            Row(
              children: [
                _tile(arts.length > 0 ? arts[0] : null, half, color),
                _tile(arts.length > 1 ? arts[1] : null, half, color),
              ],
            ),
            Row(
              children: [
                _tile(arts.length > 2 ? arts[2] : null, half, color),
                _tile(arts.length > 3 ? arts[3] : null, half, color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(List<int>? artBytes, double tileSize, Color fallback) {
    if (artBytes != null && artBytes.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(artBytes),
        width: tileSize,
        height: tileSize,
        cacheWidth: (tileSize * 2).toInt(),
        cacheHeight: (tileSize * 2).toInt(),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Container(
      width: tileSize,
      height: tileSize,
      color: fallback.withAlpha(178),
    );
  }
}
