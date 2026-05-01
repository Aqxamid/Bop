import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../widgets/receipt_widget.dart';
import '../theme/app_theme.dart';

class ShareService {
  static final ScreenshotController _screenshotController = ScreenshotController();

  static Future<Uint8List> _loadReceiptBg() async {
    final data = await rootBundle.load('assets/images/receipt_bg.png');
    return data.buffer.asUint8List();
  }

  static Future<void> sharePlaylistReceipt(BuildContext context, Playlist playlist, {List<Song>? songs}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: BopTheme.green)),
    );

    try {
      if (playlist.id != 0 && songs == null) {
        await playlist.songs.load();
      }
      final List<Song> listToShare = songs ?? playlist.songs.toList();
      
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? 'GUEST';
      final bgBytes = await _loadReceiptBg();

      final image = await _screenshotController.captureFromWidget(
        Material(child: ReceiptWidget(playlist: playlist, songs: listToShare, username: username, bgBytes: bgBytes)),
        delay: const Duration(milliseconds: 1500),
      );

      if (context.mounted) Navigator.pop(context);

      final directory = await getTemporaryDirectory();
      final imagePath = await File('${directory.path}/receipt_${playlist.id}.png').create();
      await imagePath.writeAsBytes(image);

      await Share.shareXFiles([XFile(imagePath.path)], text: 'Check out my ${playlist.name} playlist on BeatSpill!');
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      print('[ShareService] Error: $e');
    }
  }

  static Future<void> shareSongCard(BuildContext context, Song song) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: BopTheme.green)),
    );

    try {
      final image = await _screenshotController.captureFromWidget(
        Material(
          color: Colors.black,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.artBytes != null && song.artBytes!.isNotEmpty
                      ? Image.memory(Uint8List.fromList(song.artBytes!), width: 272, height: 272, fit: BoxFit.cover)
                      : Container(width: 272, height: 272, color: Colors.grey[900], child: const Icon(Icons.music_note, size: 100, color: Colors.white10)),
                ),
                const SizedBox(height: 20),
                Text(song.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(song.artist, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.music_note, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text('BOP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ],
                ),
              ],
            ),
          ),
        ),
        delay: const Duration(milliseconds: 100),
      );

      if (context.mounted) Navigator.pop(context);

      final directory = await getTemporaryDirectory();
      final imagePath = await File('${directory.path}/song_${song.id}.png').create();
      await imagePath.writeAsBytes(image);

      await Share.shareXFiles([XFile(imagePath.path)], text: 'Listening to ${song.title} by ${song.artist} on BeatSpill!');
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      print('[ShareService] Error: $e');
    }
  }

  static Future<void> shareWrappedRecap(BuildContext context, Widget summaryCard, String periodLabel) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: BopTheme.green)),
    );

    try {
      final image = await _screenshotController.captureFromWidget(
        summaryCard,
        delay: const Duration(milliseconds: 1500),
      );

      if (context.mounted) Navigator.pop(context);

      final directory = await getTemporaryDirectory();
      final imagePath = await File('${directory.path}/bop_recap_${DateTime.now().millisecondsSinceEpoch}.png').create();
      await imagePath.writeAsBytes(image);

      await Share.shareXFiles(
        [XFile(imagePath.path)],
        text: 'My $periodLabel on Bop! 🎵 #BopRecap',
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      print('[ShareService] Error sharing recap: $e');
    }
  }
}
