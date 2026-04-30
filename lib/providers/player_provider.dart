// providers/player_provider.dart
// Riverpod provider wrapping just_audio AudioPlayer with audio_service
// for system media notifications, lockscreen controls, and Dynamic Island.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../models/play_event.dart';
import '../services/db_service.dart';
import '../services/metadata_service.dart';
import '../services/llm_service.dart';
import 'stats_provider.dart';
import 'settings_provider.dart';

// ── Player state ──────────────────────────────────────────────
enum PlayerRepeatMode { off, one, all }

class PlayerState {
  final Song? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<Song> queue;
  final int currentIndex;
  final bool shuffleEnabled;
  final PlayerRepeatMode repeatMode;
  final String? djTransitionMsg;

  const PlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.currentIndex = 0,
    this.shuffleEnabled = false,
    this.repeatMode = PlayerRepeatMode.off,
    this.djTransitionMsg,
  });

  PlayerState copyWith({
    Song? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<Song>? queue,
    int? currentIndex,
    bool? shuffleEnabled,
    PlayerRepeatMode? repeatMode,
    String? djTransitionMsg,
    bool clearDjMsg = false,
    bool clearSong = false,
  }) {
    return PlayerState(
      currentSong: clearSong ? null : (currentSong ?? this.currentSong),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      djTransitionMsg: clearDjMsg ? null : (djTransitionMsg ?? this.djTransitionMsg),
    );
  }
}

// ── AudioHandler for system media notifications ──────────────
class BopAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  // Expose the underlying player so the notifier can observe streams
  AudioPlayer get player => _player;

  BopAudioHandler() {
    // Broadcast player state to system notification
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> skipToNext() async {
    // Handled by PlayerNotifier via callback
    _skipNextCallback?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    // Handled by PlayerNotifier via callback
    _skipPreviousCallback?.call();
  }

  // Callbacks set by PlayerNotifier
  VoidCallback? _skipNextCallback;
  VoidCallback? _skipPreviousCallback;

  void setSkipCallbacks({
    required VoidCallback onNext,
    required VoidCallback onPrevious,
  }) {
    _skipNextCallback = onNext;
    _skipPreviousCallback = onPrevious;
  }

  /// Update the system notification with current song info
  Future<void> updateSongNotification(Song song) async {
    Uri? artUri;
    if (song.artBytes != null && song.artBytes!.isNotEmpty) {
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/cover_${song.id}.jpg');
        if (!file.existsSync()) {
          file.writeAsBytesSync(song.artBytes!);
        }
        artUri = Uri.file(file.path);
      } catch (_) {}
    }

    mediaItem.add(MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
      artUri: artUri,
    ));
  }
}

// ── Global audio handler ─────────────────────────────────────
late BopAudioHandler audioHandler;

Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => BopAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bop.audio',
      androidNotificationChannelName: 'Bop',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}

// ── Player notifier ───────────────────────────────────────────
class PlayerNotifier extends StateNotifier<PlayerState> {
  final Ref ref;
  PlayerNotifier(this.ref) : super(const PlayerState()) {
    _init();
  }

  AudioPlayer get _player => audioHandler.player;
  final _db = DbService.instance;

  // Track current play event for updating listenedMs
  int? _currentPlayEventId;
  DateTime? _playStartTime;
  Timer? _sleepTimer;
  bool _isGaplessSkipping = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<ProcessingState>? _processingSub;

  void _init() async {
    // Set up skip callbacks for system notification controls
    audioHandler.setSkipCallbacks(
      onNext: () => skipNext(),
      onPrevious: () => skipPrevious(),
    );

    // ── Load persisted state ───────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final lastSongId = prefs.getInt('last_song_id');
    final lastPosMs = prefs.getInt('last_pos_ms') ?? 0;
    final queueIds = prefs.getStringList('last_queue_ids')?.map(int.parse).toList() ?? [];
    final lastIndex = prefs.getInt('last_index') ?? 0;
    final shuffle = prefs.getBool('shuffle_enabled') ?? false;
    final repeatIdx = prefs.getInt('repeat_mode') ?? 0;

    if (lastSongId != null) {
      final song = await _db.songs.get(lastSongId);
      if (song != null) {
        List<Song> queue = [];
        if (queueIds.isNotEmpty) {
          for (final id in queueIds) {
            final s = await _db.songs.get(id);
            if (s != null) queue.add(s);
          }
        }
        
        state = state.copyWith(
          currentSong: song,
          position: Duration(milliseconds: lastPosMs),
          queue: queue,
          currentIndex: lastIndex,
          shuffleEnabled: shuffle,
          repeatMode: PlayerRepeatMode.values[repeatIdx],
        );
        
        // Update notification first so it's ready while loading
        await audioHandler.updateSongNotification(song);

        // Prepare player but don't play
        final source = _buildConcatenatingSource(queue, lastIndex, lastPosMs);
        await _player.setAudioSource(source, initialIndex: lastIndex, initialPosition: Duration(milliseconds: lastPosMs));
      }
    }

    // Position stream - Throttled
    _positionSub = _player.positionStream.listen((pos) {
      if (mounted) {
        final diff = (pos - state.position).abs();
        if (diff.inMilliseconds >= 500 || pos.inMilliseconds < 500) {
          state = state.copyWith(position: pos);
          _savePosition(pos.inMilliseconds);
        }

        // ── Gapless (Early Skip + Crossfade) Logic ──
        final gaplessEnabled = ref.read(settingsProvider).gaplessPlayback;
        if (gaplessEnabled && state.duration.inSeconds > 0 && state.currentIndex < state.queue.length - 1) {
          final gaplessSeconds = ref.read(settingsProvider).gaplessSeconds;
          final skipThresholdMs = gaplessSeconds * 1000;
          final triggerMs = skipThresholdMs + 500; // Start fading 500ms before the skip
          
          final remainingMs = state.duration.inMilliseconds - pos.inMilliseconds;
          if (remainingMs > 0 && remainingMs <= triggerMs) {
            if (!_isGaplessSkipping) {
              _isGaplessSkipping = true;
              unawaited(_performGaplessTransition());
            }
          }
        }
      }
    });

    // Duration stream
    _durationSub = _player.durationStream.listen((dur) {
      if (mounted && dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    // Processing state (for auto-advance)
    _processingSub = _player.processingStateStream.listen((procState) {
      if (procState == ProcessingState.completed) {
        _onTrackComplete();
      }
    });

    // Index stream (for gapless sync)
    _player.currentIndexStream.listen((index) async {
      if (mounted && index != null && index != state.currentIndex && index < state.queue.length) {
        final nextSong = state.queue[index];
        state = state.copyWith(currentIndex: index, currentSong: nextSong);
        await audioHandler.updateSongNotification(nextSong);
        await _logPlayEvent(nextSong);
      }
    });

    // Playing state
    _player.playingStream.listen((playing) {
      if (mounted) {
        state = state.copyWith(isPlaying: playing);
      }
    });
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    if (state.currentSong != null) {
      await prefs.setInt('last_song_id', state.currentSong!.id);
      await prefs.setStringList('last_queue_ids', state.queue.map((s) => s.id.toString()).toList());
      await prefs.setInt('last_index', state.currentIndex);
    }
    await prefs.setBool('shuffle_enabled', state.shuffleEnabled);
    await prefs.setInt('repeat_mode', state.repeatMode.index);
  }

  ConcatenatingAudioSource _buildConcatenatingSource(List<Song> songs, int startIndex, int posMs, {bool gapless = true}) {
    return ConcatenatingAudioSource(
      useLazyPreparation: !gapless, // gapless=true → pre-buffer all (no gaps); gapless=false → lazy (normal gaps)
      children: songs.map((s) {
        if (s.uri != null && s.uri!.startsWith('content://')) {
          return AudioSource.uri(Uri.parse(s.uri!));
        }
        return AudioSource.file(s.filePath);
      }).toList(),
    );
  }

  Future<void> _savePosition(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_pos_ms', ms);
  }

  // ── Play a single song ────────────────────────────────────
  Future<void> play(Song song) async {
    await _finalizeCurrentPlayEvent(skipped: false);

    try {
      final fullSong = await _db.songs.get(song.id) ?? song;
      
      state = state.copyWith(
        currentSong: fullSong,
        position: Duration.zero,
      );
      _saveState();

      // Update notification first
      await audioHandler.updateSongNotification(fullSong);
      
      // If the song is already the current index in a concatenating source, just seek.
      // But for simplicity, we often rebuild if it's a "Play this song now" action from outside.
      // However, if we are playing from a queue, playQueue() handles it.
      
      if (state.queue.isNotEmpty && state.queue[state.currentIndex].id == song.id) {
         await _player.seek(Duration.zero, index: state.currentIndex);
      } else {
        // Fallback for single song play
        final gapless = ref.read(settingsProvider).gaplessPlayback;
        final source = _buildConcatenatingSource([fullSong], 0, 0, gapless: gapless);
        await _player.setAudioSource(source);
      }
      
      await _player.play();
      await _logPlayEvent(fullSong);
    } catch (e) {
      // File may not exist or format unsupported — skip silently
      print('[Player] Playback error: $e');
    }
  }

  // ── Play from a queue ─────────────────────────────────────
  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    // ── STEP 1: Set state IMMEDIATELY before any await so that when
    //            Navigator.push opens NowPlayingScreen synchronously,
    //            it sees the correct song/index/queue right away.
    state = state.copyWith(
      queue: songs,
      currentIndex: startIndex,
      currentSong: songs[startIndex],
      position: Duration.zero,
    );

    // ── STEP 2: Async cleanup of previous track
    await _finalizeCurrentPlayEvent(skipped: false);

    // ── STEP 3: Fetch fully-hydrated song data (artBytes, metadata)
    final List<Song> fullSongs = [];
    for (final s in songs) {
      final full = await _db.songs.get(s.id) ?? s;
      fullSongs.add(full);
    }

    // ── STEP 4: Update state with fully-hydrated songs
    final startSong = fullSongs[startIndex];
    state = state.copyWith(
      queue: fullSongs,
      currentIndex: startIndex,
      currentSong: startSong,
      position: Duration.zero,
    );
    _saveState();

    await audioHandler.updateSongNotification(startSong);

    // Build and set the concatenating audio source (gapless or not)
    final gapless = ref.read(settingsProvider).gaplessPlayback;
    final source = _buildConcatenatingSource(fullSongs, startIndex, 0, gapless: gapless);
    await _player.setAudioSource(source, initialIndex: startIndex, initialPosition: Duration.zero);
    await _player.play();
    await _logPlayEvent(startSong);
  }

  void addToQueue(Song song) {
    final newQueue = List<Song>.from(state.queue)..add(song);
    state = state.copyWith(queue: newQueue);
    _saveState();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= state.queue.length) return;
    final newQueue = List<Song>.from(state.queue);
    newQueue.removeAt(index);
    
    int newIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newIndex--;
    } else if (index == state.currentIndex) {
      // If we remove the current song, it's tricky. For now just keep index.
    }
    
    state = state.copyWith(queue: newQueue, currentIndex: newIndex);
    _saveState();
  }

  void moveQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    if (newIndex < 0 || newIndex >= state.queue.length) return;
    
    final newQueue = List<Song>.from(state.queue);
    final song = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, song);
    
    int nextCurrent = state.currentIndex;
    if (oldIndex == state.currentIndex) {
      nextCurrent = newIndex;
    } else if (oldIndex < state.currentIndex && newIndex >= state.currentIndex) {
      nextCurrent--;
    } else if (oldIndex > state.currentIndex && newIndex <= state.currentIndex) {
      nextCurrent++;
    }

    state = state.copyWith(queue: newQueue, currentIndex: nextCurrent);
    _saveState();
  }

  // ── Pause / Resume / Toggle ───────────────────────────────
  Future<void> pause() async {
    await audioHandler.pause();
    await _updateListenedMs();
  }

  Future<void> resume() async {
    await audioHandler.play();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> skipTo(int index) async {
    if (index >= 0 && index < state.queue.length) {
      if (index == state.currentIndex) {
        await _player.seek(Duration.zero);
      } else {
        await _player.seek(Duration.zero, index: index);
      }
      // state and notification will update via currentIndexStream listener
    }
  }

  Future<void> stop() async {
    await _player.stop();
    state = state.copyWith(clearSong: true, isPlaying: false, position: Duration.zero, queue: []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_song_id');
    await prefs.remove('last_queue_ids');
    await _finalizeCurrentPlayEvent(skipped: false);
  }

  Future<void> shufflePlay(List<Song> songs) async {
    final shuffled = List<Song>.from(songs)..shuffle();
    await playQueue(shuffled, startIndex: 0);
    state = state.copyWith(shuffleEnabled: true);
    _saveState();
  }

  // ── Gapless Transition (Crossfade) ────────────────────────
  Future<void> _performGaplessTransition() async {
    const fadeOutSteps = 10;
    const stepDuration = Duration(milliseconds: 50); // 500ms total fade

    // 1. Fade out
    for (int i = 0; i < fadeOutSteps; i++) {
      if (!mounted) return;
      await _player.setVolume(1.0 - (i / fadeOutSteps));
      await Future.delayed(stepDuration);
    }
    await _player.setVolume(0.0);
    
    // 2. Skip to next song
    await skipNext();
    
    // 3. Fade in
    for (int i = 1; i <= fadeOutSteps; i++) {
      if (!mounted) return;
      await _player.setVolume(i / fadeOutSteps);
      await Future.delayed(stepDuration);
    }
    await _player.setVolume(1.0);
    
    // Cooldown
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _isGaplessSkipping = false;
    });
  }

  // ── Skip ──────────────────────────────────────────────────
  Future<void> skipNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      if (state.repeatMode == PlayerRepeatMode.all) {
        await _player.seek(Duration.zero, index: 0);
      } else {
        // AI DJ Infinite Queue
        if (state.currentSong != null) {
          final vibeResult = await LlmService.instance.generateNextVibeSong(state.currentSong!);
          if (vibeResult != null) {
            final nextSong = vibeResult.key;
            final transition = vibeResult.value;
            final newQueue = List<Song>.from(state.queue)..add(nextSong);
            state = state.copyWith(queue: newQueue, djTransitionMsg: transition);
            
            // Append to source and let it transition
            final source = _player.audioSource as ConcatenatingAudioSource?;
            if (source != null) {
              await source.add(AudioSource.file(nextSong.filePath));
              await _player.seekToNext();
            }
          }
        }
      }
    }
  }

  Future<void> skipPrevious() async {
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      if (state.repeatMode == PlayerRepeatMode.all && state.queue.isNotEmpty) {
        await _player.seek(Duration.zero, index: state.queue.length - 1);
      } else {
        await _player.seek(Duration.zero);
      }
    }
  }

  // ── Seek ──────────────────────────────────────────────────
  Future<void> seek(Duration position) async {
    await audioHandler.seek(position);
  }

  /// Remove a song from the active queue (e.g. when hidden from library)
  void removeSong(int songId) {
    if (state.queue.isEmpty) return;
    
    final indexInQueue = state.queue.indexWhere((s) => s.id == songId);
    if (indexInQueue != -1) {
      final newQueue = List<Song>.from(state.queue);
      newQueue.removeAt(indexInQueue);
      
      if (state.currentIndex == indexInQueue) {
        if (newQueue.isNotEmpty) {
          final nextIndex = state.currentIndex >= newQueue.length ? 0 : state.currentIndex;
          state = state.copyWith(queue: newQueue, currentIndex: nextIndex);
          play(newQueue[nextIndex]);
        } else {
          _player.stop();
          state = state.copyWith(queue: [], currentIndex: 0, currentSong: null, isPlaying: false, position: Duration.zero);
        }
      } else if (state.currentIndex > indexInQueue) {
        state = state.copyWith(queue: newQueue, currentIndex: state.currentIndex - 1);
      } else {
        state = state.copyWith(queue: newQueue);
      }
    }
  }

  // ── Shuffle & Repeat ──────────────────────────────────────
  void toggleShuffle() async {
    final enabled = !state.shuffleEnabled;
    state = state.copyWith(shuffleEnabled: enabled);
    
    await _player.setShuffleModeEnabled(enabled);
    if (enabled) {
      await _player.shuffle();
    }
    
    _saveState();
  }

  void toggleRepeat() {
    final modes = PlayerRepeatMode.values;
    final nextIndex =
        (modes.indexOf(state.repeatMode) + 1) % modes.length;
    state = state.copyWith(repeatMode: modes[nextIndex]);
    _saveState();
  }

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) return;

    _sleepTimer = Timer(Duration(minutes: minutes), () {
      pause();
    });
  }

  // ── Like toggle ───────────────────────────────────────────
  Future<void> toggleLike() async {
    final song = state.currentSong;
    if (song == null) return;

    song.isLiked = !song.isLiked;
    await _db.isar.writeTxn(() async {
      await _db.songs.put(song);
    });
    
    // Invalidate providers to sync UI
    ref.invalidate(allSongsProvider);
    ref.invalidate(likedSongsProvider);
    
    state = state.copyWith(currentSong: song);
  }

  Future<void> refreshCurrentSong() async {
    if (state.currentSong == null) return;
    final fresh = await _db.songs.get(state.currentSong!.id);
    if (fresh != null) {
      state = state.copyWith(currentSong: fresh);
    }
  }

  // ── Track completion handler ──────────────────────────────
  Future<void> _onTrackComplete() async {
    await _finalizeCurrentPlayEvent(skipped: false);

    if (state.repeatMode == PlayerRepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    // Strict Loop/Repeat Off enforcement
    if (state.repeatMode == PlayerRepeatMode.off && state.currentIndex >= state.queue.length - 1) {
      // Check if AI is enabled for auto-extension
      final aiEnabled = ref.read(settingsProvider).aiEnabled;
      if (!aiEnabled) {
        await pause();
        return;
      }
    }

    await skipNext();
  }

  // ── PlayEvent logging ─────────────────────────────────────
  Future<void> _logPlayEvent(Song song) async {
    _playStartTime = DateTime.now();
    
    // Perform metadata fetch in BACKGROUND - don't await it to prevent playback lag
    unawaited(_backgroundMetadataUpdate(song));

    final event = PlayEvent()
      ..songTitle = song.title
      ..artist = song.artist
      ..genre = song.genre
      ..startedAt = _playStartTime!;

    await _db.isar.writeTxn(() async {
      _currentPlayEventId = await _db.playEvents.put(event);
      event.song.value = song;
      await event.song.save();
    });

    // Increment play count
    song.playCount++;
    song.lastPlayedAt = _playStartTime;
    await _db.isar.writeTxn(() async {
      await _db.songs.put(song);
    });
  }

  Future<void> _backgroundMetadataUpdate(Song song) async {
    if (song.genre == 'Unknown' || song.artist == 'Unknown Artist' || song.album == 'Unknown Album') {
      try {
        final updated = await MetadataService.instance.fetchAndFillMetadata(song);
        if (updated && mounted) {
          // Success! Refresh providers to show new info in UI
          ref.invalidate(recentSongsProvider);
          ref.invalidate(genreBreakdownProvider);
          ref.invalidate(topArtistsProvider);
          ref.invalidate(minutesProvider);
          ref.invalidate(allSongsProvider);
        }
      } catch (e) {
        print('[Player] Background metadata fetch failed: $e');
      }
    }
  }

  Future<void> _updateListenedMs() async {
    if (_currentPlayEventId == null || _playStartTime == null) return;

    final listenedMs = state.position.inMilliseconds;
    final event = await _db.playEvents.get(_currentPlayEventId!);
    if (event != null) {
      event.listenedMs = listenedMs;
      await _db.isar.writeTxn(() async {
        await _db.playEvents.put(event);
      });
    }
  }

  Future<void> _finalizeCurrentPlayEvent({required bool skipped}) async {
    if (_currentPlayEventId == null) return;

    final listenedMs = state.position.inMilliseconds;
    final event = await _db.playEvents.get(_currentPlayEventId!);
    if (event != null) {
      event.listenedMs = listenedMs;
      event.wasSkipped = skipped;
      await _db.isar.writeTxn(() async {
        await _db.playEvents.put(event);
      });
    }

    // Update skip count on the song
    if (skipped && state.currentSong != null) {
      final song = state.currentSong!;
      song.skipCount++;
      await _db.isar.writeTxn(() async {
        await _db.songs.put(song);
      });
    }

    _currentPlayEventId = null;
    _playStartTime = null;
  }

  bool _isSkippedEarly() {
    if (state.duration.inMilliseconds == 0) return false;
    return state.position.inMilliseconds <
        (state.duration.inMilliseconds * 0.5);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _processingSub?.cancel();
    super.dispose();
  }
}

// ── Provider ────────────────────────────────────────────────
final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref);
});
