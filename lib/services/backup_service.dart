import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../models/play_event.dart';
import '../models/wrapped_report.dart';
import 'db_service.dart';
import 'package:isar/isar.dart';

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  final _db = DbService.instance;

  Future<String?> createBackup() async {
    final songs = await _db.songs.where().findAll();
    final playlists = await _db.playlists.where().findAll();
    final events = await _db.playEvents.where().findAll();

    final reports = await _db.wrappedReports.where().findAll();

    // ── Load Settings ───────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    final keys = prefs.getKeys();
    for (final key in keys) {
      final val = prefs.get(key);
      if (!key.contains('last_song') && !key.contains('last_pos') && !key.contains('last_index')) {
        settings[key] = val;
      }
    }

    final backupData = {
      'version': '2.6.2',
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings,
      'songs': songs.map((s) => {
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'genre': s.genre,
        'durationMs': s.durationMs,
        'playCount': s.playCount,
        'skipCount': s.skipCount,
        'isLiked': s.isLiked,
        'isHidden': s.isHidden,
        'lyrics': s.lyrics,
        'fileName': s.filePath.split('/').last,
      }).toList(),
      'playlists': playlists.map((p) => {
        'name': p.name,
        'coverColor': p.coverColor,
        'isAiGenerated': p.isAiGenerated,
        'createdAt': p.createdAt.toIso8601String(),
        'songFingerprints': p.songs.map((s) => '${s.filePath.split('/').last}|${s.durationMs}').toList(),
      }).toList(),
      'events': events.map((e) => {
        'songFingerprint': e.song.value != null ? '${e.song.value!.filePath.split('/').last}|${e.song.value!.durationMs}' : null,
        'songTitle': e.songTitle,
        'artist': e.artist,
        'genre': e.genre,
        'listenedMs': e.listenedMs,
        'startedAt': e.startedAt.toIso8601String(),
        'wasSkipped': e.wasSkipped,
      }).toList(),
      'wrappedReports': reports.map((r) => {
        'periodLabel': r.periodLabel,
        'cadence': r.cadence,
        'generatedAt': r.generatedAt.toIso8601String(),
        'totalMinutes': r.totalMinutes,
        'totalSongs': r.totalSongs,
        'streakDays': r.streakDays,
        'skipRate': r.skipRate,
        'topArtist': r.topArtist,
        'topArtistPlays': r.topArtistPlays,
        'topSong': r.topSong,
        'peakHourLabel': r.peakHourLabel,
        'personalityType': r.personalityType,
        'personalityEmoji': r.personalityEmoji,
        'genreJsonStr': r.genreJsonStr,
        'llmRecap': r.llmRecap,
        'isAiGenerated': r.isAiGenerated,
        'slidesJsonStr': r.slidesJsonStr,
      }).toList(),
    };

    final jsonStr = jsonEncode(backupData);
    final directory = await getApplicationDocumentsDirectory();
    
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    
    final file = File('${directory.path}/bop_backup_${mm}${dd}${yy}_${hh}${min}.json');
    await file.writeAsString(jsonStr);

    return file.path;
  }

  Future<Map<String, int>> restoreBackup(String path) async {
    final file = File(path);
    final jsonStr = await file.readAsString();
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final Map<String, dynamic> settingsData = data['settings'] ?? {};
    final List<dynamic> songsData = data['songs'] ?? [];
    final List<dynamic> playlistsData = data['playlists'] ?? [];
    final List<dynamic> eventsData = data['events'] ?? [];
    final List<dynamic> reportsData = data['wrappedReports'] ?? [];

    int songsRestored = 0;
    int playlistsRestored = 0;
    int eventsRestored = 0;
    int reportsRestored = 0;

    // 1. Restore Settings
    final prefs = await SharedPreferences.getInstance();
    for (final entry in settingsData.entries) {
      final key = entry.key;
      final val = entry.value;
      if (val is bool) await prefs.setBool(key, val);
      else if (val is int) await prefs.setInt(key, val);
      else if (val is double) await prefs.setDouble(key, val);
      else if (val is String) await prefs.setString(key, val);
      else if (val is List) await prefs.setStringList(key, List<String>.from(val));
    }

    await _db.isar.writeTxn(() async {
      final existingSongs = await _db.songs.where().findAll();
      
      // 2. Restore Song Metadata
      for (final sData in songsData) {
        final fileName = sData['fileName'] ?? '';
        final duration = sData['durationMs'] ?? 0;
        
        // Match by Filename + Duration (Most robust for cross-device moves)
        final match = existingSongs.where((s) {
          final sName = s.filePath.split('/').last;
          return sName == fileName && (s.durationMs - duration).abs() < 1000;
        }).firstOrNull;
        
        if (match != null) {
          match.title = sData['title'] ?? match.title;
          match.artist = sData['artist'] ?? match.artist;
          match.playCount = sData['playCount'] ?? match.playCount;
          match.skipCount = sData['skipCount'] ?? match.skipCount;
          match.isLiked = sData['isLiked'] ?? match.isLiked;
          match.isHidden = sData['isHidden'] ?? match.isHidden;
          match.lyrics = sData['lyrics'] ?? match.lyrics;
          match.genre = sData['genre'] ?? match.genre;
          await _db.songs.put(match);
          songsRestored++;
        }
      }

      // 3. Restore Playlists
      for (final pData in playlistsData) {
        final name = pData['name'];
        var playlist = await _db.playlists.where().filter().nameEqualTo(name).findFirst();
        if (playlist == null) {
          playlist = Playlist()
            ..name = name
            ..coverColor = pData['coverColor'] ?? '#1DB954'
            ..isAiGenerated = pData['isAiGenerated'] ?? false
            ..createdAt = pData['createdAt'] != null ? DateTime.parse(pData['createdAt']) : DateTime.now();
          await _db.playlists.put(playlist);
        }

        final fingerprints = List<String>.from(pData['songFingerprints'] ?? []);
        final List<Song> playlistSongs = [];
        for (final fp in fingerprints) {
          final match = existingSongs.where((s) {
            final sName = s.filePath.split('/').last;
            return '$sName|${s.durationMs}' == fp;
          }).firstOrNull;
          
          if (match != null) playlistSongs.add(match);
        }
        playlist.songs.addAll(playlistSongs);
        await playlist.songs.save();
        playlistsRestored++;
      }

      // 4. Restore PlayEvents
      final existingEvents = await _db.playEvents.where().findAll();
      for (final eData in eventsData) {
        final startedAt = DateTime.parse(eData['startedAt']);
        final fp = eData['songFingerprint'];
        if (fp == null) continue;

        // Deduplicate
        final exists = existingEvents.any((e) => 
          e.startedAt.isAtSameMomentAs(startedAt) && 
          e.listenedMs == eData['listenedMs']
        );
        if (exists) continue;

        final match = existingSongs.where((s) {
          final sName = s.filePath.split('/').last;
          return '$sName|${s.durationMs}' == fp;
        }).firstOrNull;

        final event = PlayEvent()
          ..listenedMs = eData['listenedMs'] ?? 0
          ..startedAt = startedAt
          ..wasSkipped = eData['wasSkipped'] ?? false
          ..songTitle = eData['songTitle'] ?? (match?.title ?? 'Unknown')
          ..artist = eData['artist'] ?? (match?.artist ?? 'Unknown Artist')
          ..genre = eData['genre'] ?? (match?.genre ?? 'Unknown');
        
        await _db.playEvents.put(event);
        if (match != null) {
          event.song.value = match;
          await event.song.save();
        }
        eventsRestored++;
      }

      // 5. Restore WrappedReports
      final existingReports = await _db.wrappedReports.where().findAll();
      for (final rData in reportsData) {
        final generatedAt = DateTime.parse(rData['generatedAt']);
        final period = rData['periodLabel'];
        
        final exists = existingReports.any((r) => 
          r.periodLabel == period && r.generatedAt.isAtSameMomentAs(generatedAt)
        );
        if (exists) continue;

        final report = WrappedReport()
          ..periodLabel = period
          ..cadence = rData['cadence'] ?? 'monthly'
          ..generatedAt = generatedAt
          ..totalMinutes = rData['totalMinutes'] ?? 0
          ..totalSongs = rData['totalSongs'] ?? 0
          ..streakDays = rData['streakDays'] ?? 0
          ..skipRate = (rData['skipRate'] ?? 0.0).toDouble()
          ..topArtist = rData['topArtist'] ?? 'Unknown'
          ..topArtistPlays = rData['topArtistPlays'] ?? 0
          ..topSong = rData['topSong'] ?? 'Unknown'
          ..peakHourLabel = rData['peakHourLabel'] ?? '12pm'
          ..personalityType = rData['personalityType'] ?? 'Musical Explorer'
          ..personalityEmoji = rData['personalityEmoji'] ?? 'explore'
          ..genreJsonStr = rData['genreJsonStr'] ?? '{}'
          ..llmRecap = rData['llmRecap'] ?? ''
          ..isAiGenerated = rData['isAiGenerated'] ?? false
          ..slidesJsonStr = rData['slidesJsonStr'] ?? '';
        
        await _db.wrappedReports.put(report);
        reportsRestored++;
      }
    });

    return {
      'songs': songsRestored,
      'playlists': playlistsRestored,
      'events': eventsRestored,
      'reports': reportsRestored,
    };
  }
}
