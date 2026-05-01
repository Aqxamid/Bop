// providers/stats_provider.dart
// Riverpod providers for all stats data used in StatsScreen and HomeScreen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../services/db_service.dart';
import '../services/lyrics_service.dart';
import '../models/song.dart';
import '../services/llm_service.dart';

// ── Period state ─────────────────────────────────────────────
enum StatsPeriod { week, month, quarter, allTime }

final statsPeriodProvider = StateProvider<StatsPeriod>((ref) => StatsPeriod.month);

/// DEBUG: Allows mocking the date to test November/December Recap cards.
final debugDateProvider = StateProvider<DateTime?>((ref) => null);

// Helper to calculate date range based on period
(DateTime, DateTime) _getRange(StatsPeriod period) {
  final now = DateTime.now();
  switch (period) {
    case StatsPeriod.week:
      return (now.subtract(const Duration(days: 7)), now);
    case StatsPeriod.quarter:
      return (now.subtract(const Duration(days: 90)), now);
    case StatsPeriod.allTime:
      return (DateTime(2000), now);
    case StatsPeriod.month:
    default:
      return (DateTime(now.year, now.month, 1), now);
  }
}

// ── Minutes listened ─────────────────────────────────────────
final minutesProvider = FutureProvider<int>((ref) async {
  final period = ref.watch(statsPeriodProvider);
  final range = _getRange(period);
  return DbService.instance.minutesForRange(range.$1, range.$2);
});

// ── Song count ───────────────────────────────────────────────
final songCountProvider = FutureProvider<int>((ref) async {
  final period = ref.watch(statsPeriodProvider);
  final range = _getRange(period);
  return DbService.instance.songsForRange(range.$1, range.$2);
});

// ── Current streak ───────────────────────────────────────────
final streakProvider = FutureProvider<int>((ref) async {
  return DbService.instance.currentStreak();
});

// ── Skip rate ────────────────────────────────────────────────
final skipRateProvider = FutureProvider<double>((ref) async {
  return DbService.instance.overallSkipRate();
});

// ── Heatmap ──────────────────────────────────────────────────
final heatmapProvider = FutureProvider<List<List<int>>>((ref) async {
  final period = ref.watch(statsPeriodProvider);
  final range = _getRange(period);
  return DbService.instance.heatmapForRange(range.$1, range.$2);
});

// ── Genre breakdown ──────────────────────────────────────────
final genreBreakdownProvider = FutureProvider<Map<String, int>>((ref) async {
  final period = ref.watch(statsPeriodProvider);
  final range = _getRange(period);
  return DbService.instance.genreBreakdownForRange(range.$1, range.$2);
});

// ── Top artists ──────────────────────────────────────────────
final topArtistsProvider =
    FutureProvider<List<MapEntry<String, int>>>((ref) async {
  final period = ref.watch(statsPeriodProvider);
  final range = _getRange(period);
  return DbService.instance
      .topArtistsForRange(range.$1, range.$2, limit: 5);
});

// ── Recently played songs (for HomeScreen) ───────────────────
final recentSongsProvider = FutureProvider<List<Song>>((ref) async {
  // Get all songs that have been played, then sort by lastPlayedAt
  final songs = await DbService.instance.songs
      .filter()
      .isHiddenEqualTo(false)
      .and()
      .lastPlayedAtIsNotNull()
      .findAll();
  songs.sort((a, b) => (b.lastPlayedAt ?? DateTime(0))
      .compareTo(a.lastPlayedAt ?? DateTime(0)));
  return songs.take(10).toList();
});

// ── All songs (for Library/Search) ───────────────────────────
final allSongsProvider = FutureProvider<List<Song>>((ref) async {
  final list = await DbService.instance.songs.filter().isHiddenEqualTo(false).findAll();
  // Sort alphabetically by title, case-insensitive
  list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return list;
});

// ── Liked songs ──────────────────────────────────────────────
final likedSongsProvider = FutureProvider<List<Song>>((ref) async {
  return DbService.instance.songs
      .filter()
      .isLikedEqualTo(true)
      .and()
      .isHiddenEqualTo(false)
      .findAll();
});

// ── Tab navigation provider ──────────────────────────────────
// Tracks whether LLM model is actually loaded in RAM (reactive)
final llmModelReadyProvider = StateProvider<bool>((ref) => LlmService.instance.isModelLoaded);

final shellTabIndexProvider = StateProvider<int>((ref) => 0);
final searchGenreProvider = StateProvider<String?>((ref) => null);

// ── Lyrics fetching ──────────────────────────────────────────
final lyricsProvider = FutureProvider.family<String?, Song>((ref, song) async {
  // Use a separate service for lyrics
  final lyrics = await LyricsService.instance.fetchLyrics(song);
  return lyrics;
});



// ── AI Curated Playlists ─────────────────────────────────────
final aiPlaylistsProvider = FutureProvider<List<SmartPlaylistData>>((ref) async {
  ref.keepAlive(); // Keep the AI playlists in memory to prevent flickering
  // Re-run this provider whenever the LLM model state changes
  ref.watch(llmModelReadyProvider);
  return LlmService.instance.generateSmartPlaylists();
});

// ── Hidden Gems (Least played songs) ──────────────────────────
final hiddenGemsProvider = FutureProvider<List<Song>>((ref) async {
  final all = await DbService.instance.songs.filter().isHiddenEqualTo(false).findAll();
  all.sort((a, b) => a.playCount.compareTo(b.playCount));
  return all.take(10).toList();
});

// ── Playlist Gems (1-2 songs from each playlist) ─────────────
final playlistGemsProvider = FutureProvider<List<Song>>((ref) async {
  final playlists = await DbService.instance.playlists.where().findAll();
  final List<Song> gems = [];
  for (final p in playlists) {
    await p.songs.load();
    final songs = p.songs.toList();
    if (songs.isNotEmpty) {
      songs.shuffle();
      gems.addAll(songs.take(2));
    }
  }
  gems.shuffle();
  return gems.take(20).toList();
});

// ── Artist & Album Filter Caching ────────────────────────────
final artistSongsProvider = FutureProvider.family<List<Song>, String>((ref, artist) async {
  final allSongs = await ref.watch(allSongsProvider.future);
  return allSongs.where((s) => s.artist.toLowerCase() == artist.toLowerCase()).toList();
});

final albumSongsProvider = FutureProvider.family<List<Song>, String>((ref, album) async {
  final allSongs = await ref.watch(allSongsProvider.future);
  return allSongs.where((s) => s.album.toLowerCase() == album.toLowerCase()).toList();
});
