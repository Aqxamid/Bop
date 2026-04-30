import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/song.dart';
import '../models/playlist.dart';

class ReceiptWidget extends StatelessWidget {
  final Playlist playlist;
  final List<Song>? songs;
  const ReceiptWidget({super.key, required this.playlist, this.songs});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, y').format(now).toUpperCase();
    final timeStr = DateFormat('h:mm a').format(now).toUpperCase();
    final displaySongs = songs ?? playlist.songs.toList();

    return Container(
      width: 320,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'BOP',
            style: TextStyle(
              color: Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              fontFamily: 'Courier',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ORDER #0001 FOR GUEST',
            style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 10, fontFamily: 'Courier'),
          ),
          Text(
            '$dateStr $timeStr',
            style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 10, fontFamily: 'Courier'),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.black26, thickness: 1),
          const SizedBox(height: 16),
          
          // Songs List (Limited to 6)
          ...displaySongs.take(6).map((song) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title.toUpperCase(),
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        song.artist.toUpperCase(),
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontFamily: 'Courier'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatMs(song.durationMs),
                  style: const TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'Courier'),
                ),
              ],
            ),
          )).toList(),

          if (displaySongs.length > 6)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'AND ${displaySongs.length - 6} MORE...',
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
              ),
            ),

          const SizedBox(height: 16),
          const Divider(color: Colors.black26, thickness: 1),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ITEM COUNT:', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              Text('${displaySongs.length}', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'THANK YOU FOR VISITING!',
            style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          ),
          const SizedBox(height: 12),
          // Barcode Placeholder
          Container(
            height: 40,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(20, (i) => Container(width: i % 3 == 0 ? 4 : 1, color: Colors.black)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('beatspill.bop', style: TextStyle(color: Colors.black54, fontSize: 8, fontFamily: 'Courier')),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}
