// services/llm_service.dart
// Local on-device text generator for Wrapped recaps.
// Attempts to use fllama (TinyLlama GGUF) if a model file exists on-device.
// Falls back to smart template-based generation (no external API calls).
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/playlist.dart';
import '../models/wrapped_report.dart';
import 'db_service.dart';
import 'lyrics_service.dart';
import 'package:isar/isar.dart';

class SmartPlaylistData {
  final String name;
  final List<Song> songs;
  final bool isAiGenerated;
  SmartPlaylistData({required this.name, required this.songs, this.isAiGenerated = false});
}

class LlmService {
  LlmService._();
  static final LlmService instance = LlmService._();

  static const _apiKeyPref = 'llm_api_key';
  static const _modelPathPref = 'llm_model_path';
  static const _aiEnabledPref = 'llm_ai_enabled';
  static const _modelNamePref = 'llm_model_name';
  static const _playlistCachePref = 'cached_smart_playlists';
  static const _playlistUpdatePref = 'last_playlist_update_date';

  String _cachedApiKey = '';
  String _modelPath = '';
  LlamaController? _llama;
  bool _modelAvailable = false;
  bool _modelLoaded = false;
  bool _isAiEnabled = true;

  final modelStatus = ValueNotifier<String?>(null);
  final isModelLoading = ValueNotifier<bool>(false);
  final modelName = ValueNotifier<String?>(null);
  final generationProgress = ValueNotifier<int>(0);
  List<SmartPlaylistData>? _cachedPlaylists;
  DateTime? _lastPlaylistUpdate;
  Future<void>? _loadFuture;

  bool get isAiEnabled => _isAiEnabled;
  bool get isModelLoaded => _modelLoaded;

  Future<String> get currentApiKey async {
    if (_cachedApiKey.isNotEmpty) return _cachedApiKey;
    final prefs = await SharedPreferences.getInstance();
    _cachedApiKey = prefs.getString(_apiKeyPref) ?? '';
    return _cachedApiKey;
  }

  Future<void> updateApiKey(String key) async {
    _cachedApiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key);
  }

  Future<String> get currentModelPath async {
    if (_modelPath.isNotEmpty) return _modelPath;
    final prefs = await SharedPreferences.getInstance();
    _modelPath = prefs.getString(_modelPathPref) ?? '';
    return _modelPath;
  }

  Future<void> updateModelPath(String path) async {
    _modelPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelPathPref, path);
    _modelAvailable = path.isNotEmpty && await File(path).exists();
  }

  Future<void> loadModel([String? modelPath]) async {
    final prefs = await SharedPreferences.getInstance();
    _isAiEnabled = prefs.getBool(_aiEnabledPref) ?? true;
    modelName.value = prefs.getString(_modelNamePref);

    if (!_isAiEnabled) {
      modelStatus.value = "AI Sleeping (RAM freed)";
      return;
    }
    _loadFuture = _loadModelInternal(modelPath);
    return _loadFuture;
  }

  Future<void> setAiEnabled(bool enabled) async {
    _isAiEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiEnabledPref, enabled);

    if (enabled) {
      final path = await currentModelPath;
      if (path.isNotEmpty) {
        await loadModel(path);
      } else {
        modelStatus.value = null;
      }
    } else {
      await disposeModel();
      modelStatus.value = "AI Sleeping (RAM Freed) 💤";
    }
  }

  Future<void> _loadModelInternal([String? modelPath]) async {
    isModelLoading.value = true;
    try {
      final path = modelPath ?? await currentModelPath;
      if (path.isEmpty) return;

      File modelFile = File(path);
      if (!await modelFile.exists()) {
        _modelAvailable = false;
        return;
      }

      bool isCachePath = path.contains('/cache/') || path.contains('/com.android.providers');
      final docDir = await getApplicationDocumentsDirectory();
      bool isAlreadyInDocs = path.contains(docDir.path);

      final originalName = path.split('/').last;
      if (modelName.value == null || modelName.value != originalName) {
        modelName.value = originalName;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_modelNamePref, originalName);
      }

      if (isCachePath && !isAlreadyInDocs) {
        try {
          final docDir = await getApplicationDocumentsDirectory();
          final newPath = '${docDir.path}/model.gguf';

          if (path != newPath) {
            print('[LLM] Moving model to internal storage for persistence...');
            final newFile = File(newPath);

            if (await newFile.exists()) await newFile.delete();
            await modelFile.copy(newPath);

            modelFile = newFile;
            await updateModelPath(newPath);
            print('[LLM] Model persisted at: $newPath');
          }
        } catch (e) {
          print('[LLM] Failed to persist model: $e');
          print('[LLM] Proceeding with temporary cache path...');
        }
      }

      await disposeModel();

      try {
        modelStatus.value = "AI: Loading LLM model into RAM...";
        print('[LLM] Attempting to load model from: ${modelFile.path}');
        _llama = LlamaController();
        await _llama!.loadModel(modelPath: modelFile.path);

        _modelAvailable = true;
        _modelLoaded = true;
        _modelPath = modelFile.path;
        modelStatus.value = "AI: Model Ready (Local AI Active)!";
        
        // Invalidate playlist cache to force regeneration with AI now that model is ready
        _cachedPlaylists = null;
        _lastPlaylistUpdate = null; // Also clear disk cache date so it forces full regeneration
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_playlistCachePref);
          await prefs.remove(_playlistUpdatePref);
        } catch (_) {}
        
        Future.delayed(const Duration(seconds: 3), () {
          if (modelStatus.value != null && modelStatus.value!.contains('Ready')) {
            modelStatus.value = null;
          }
        });
        print('[LLM] Model loaded successfully');
      } catch (e) {
        final errorStr = e.toString();
        String userMessage = errorStr;

        if (errorStr.contains('libllama.so') || errorStr.contains('dlopen failed')) {
          userMessage = 'Native library incompatible. Use physical ARM64 device.';
        }

        print('[LLM] Error loading model: $userMessage');
        modelStatus.value = "Error: $userMessage";
        _modelAvailable = false;
        _modelLoaded = false;
        throw Exception(userMessage);
      }
    } finally {
      isModelLoading.value = false;
    }
  }

  Future<void> disposeModel() async {
    try {
      if (_modelLoaded || _llama != null) {
        modelStatus.value = "Unloading model...";
        await _llama?.dispose();
        _llama = null;
        _modelLoaded = false;
        _modelAvailable = false;
        modelStatus.value = "Model unloaded (RAM freed)";
      }
    } catch (e) {
      print('[LLM] Error disposing model: $e');
      modelStatus.value = "Error unloading: $e";
    }
  }

  Future<void> clearModel() async {
    await disposeModel();
    final path = await currentModelPath;
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modelNamePref);
    modelName.value = null;

    await updateModelPath('');
    modelStatus.value = "Model cleared (File deleted)";
  }

  // ── Core prompt builder for tiny local LLMs ───────────────────────────────
  // Designed for TinyLlama-1.1B, Gemma-3-1B, and Llama-3.2-1B-Instruct Q5_K_M.
  // Rules: short context, no multi-turn, direct fill-in format, no meta-commentary.
  // All prompts use a "fill in the blank" pattern so the model just continues text
  // rather than answering — dramatically reduces hallucination on sub-2B models.

  /// Wraps a prompt for the detected/assumed model format.
  String _wrapPrompt(String instruction, String responsePrefix) {
    final name = (modelName.value ?? '').toLowerCase();
    if (name.contains('gemma')) {
      return '<start_of_turn>user\n$instruction<end_of_turn>\n<start_of_turn>model\n$responsePrefix';
    }
    return '<s>[INST] $instruction [/INST]\n$responsePrefix';
  }

  // ── AI-driven song curation ───────────────────────────────────────────────
  //
  // Instead of just renaming a shuffle, the LLM scores each song against a
  // "vibe profile" derived from the user's listening behaviour. The score is
  // a weighted sum of three on-device signals so nothing leaves the device:
  //
  //   playScore  — normalised play-count (loyalty signal)
  //   freshScore — recency of last play   (momentum signal)
  //   moodScore  — LLM vibe-match        (0 or 1, only when model is loaded)
  //
  // Without LLM the first two signals still produce a meaningfully different
  // ordering from a raw shuffle, so algo playlists also improve.

  /// Derives a compact "vibe tag" for a song from its metadata.
  /// Used as a lightweight stand-in for audio-feature analysis.
  String _songVibeTag(Song song) {
    final g = song.genre.toLowerCase();

    // Chill / soft textures
    if (g.contains('lo-fi') || g.contains('chill') || g.contains('ambient')) return 'chill';
    if (g.contains('acoustic') || g.contains('folk')) return 'mellow';
    if (g.contains('piano') || g.contains('instrumental')) return 'serene';

    // Energy / intensity
    if (g.contains('rock') || g.contains('metal') || g.contains('punk')) return 'energetic';
    if (g.contains('hardcore') || g.contains('grunge')) return 'aggressive';

    // Groove / rhythm-driven
    if (g.contains('funk') || g.contains('disco')) return 'groovy';
    if (g.contains('r&b') || g.contains('soul')) return 'smooth';

    // Emotional tones
    if (g.contains('blues')) return 'melancholic';
    if (g.contains('emo') || g.contains('sad')) return 'emotional';
    if (g.contains('romance') || g.contains('love')) return 'romantic';
    if (g.contains('throwback') || g.contains('retro')) return 'nostalgic';

    // Mainstream / general vibes
    if (g.contains('pop')) return 'upbeat';
    if (g.contains('indie')) return 'dreamy';

    // Rap / hype spectrum
    if (g.contains('hip') || g.contains('rap') || g.contains('trap')) return 'hype';
    if (g.contains('drill')) return 'gritty';

    // Electronic spectrum
    if (g.contains('edm') || g.contains('dance')) return 'party';
    if (g.contains('house') || g.contains('techno')) return 'electric';
    if (g.contains('synth') || g.contains('wave')) return 'atmospheric';

    // Classical / cinematic
    if (g.contains('classical') || g.contains('orchestral')) return 'focused';
    if (g.contains('soundtrack') || g.contains('score')) return 'cinematic';
    if (g.contains('epic')) return 'epic';

    // Gospel / worship
    if (g.contains('worship') || g.contains('gospel')) return 'uplifting';

    // Fallback: smarter momentum heuristic
    if (song.playCount > 50) return 'intense';
    if (song.playCount > 25) return 'energetic';
    if (song.playCount > 10) return 'upbeat';

    return 'chill';
  }

  /// Ask the LLM to pick the best vibe-tag for a playlist theme in one token.
  /// validTags set matches the full expanded const tags list.
  Future<String> _askLlmForVibeTag(String genre, String activityHint) async {
    if (!_modelAvailable || !_modelLoaded || _llama == null || !_isAiEnabled) return '';

    const tags =
        'chill, energetic, soulful, upbeat, hype, focused, electric, mellow, '
        'dreamy, dark, atmospheric, romantic, nostalgic, groovy, aggressive, uplifting, '
        'emotional, cinematic, funky, gritty, smooth, melancholic, party, ethereal, '
        'intense, serene, playful, epic';

    // Must stay in sync with const tags above
    const validTags = {
      'chill', 'energetic', 'soulful', 'upbeat', 'hype', 'focused', 'electric', 'mellow',
      'dreamy', 'dark', 'atmospheric', 'romantic', 'nostalgic', 'groovy', 'aggressive',
      'uplifting', 'emotional', 'cinematic', 'funky', 'gritty', 'smooth', 'melancholic',
      'party', 'ethereal', 'intense', 'serene', 'playful', 'epic',
    };

    final instruction =
        'A listener who loves $genre music is about to listen $activityHint. '
        'Which single word best describes the ideal vibe? '
        'Choose ONLY one from: $tags. Output only the one word.';
    final prompt = _wrapPrompt(instruction, 'Vibe:');

    try {
      if (!_modelLoaded || _llama == null) return '';
      final stream = _llama!.generate(prompt: prompt, maxTokens: 6);
      String raw = '';
      await for (final token in stream) {
        if (!_modelLoaded || _llama == null) break;
        raw += token;
        if (raw.length > 30) break; // safety cap
      }
      final word = raw
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z]'), ' ')
          .trim()
          .split(' ')
          .firstWhere(
            (w) => validTags.contains(w),
            orElse: () => '',
          );
      print('[LLM] Vibe tag for $genre: $word');
      return word;
    } catch (e) {
      print('[LLM] Vibe tag error: $e');
      return '';
    }
  }

  /// Returns a 0-1 float: how strongly does this song match the target vibe?
  double _vibeMatchScore(Song song, String targetVibe) {
    if (targetVibe.isEmpty) return 0.5; // neutral — no LLM result
    final songVibe = _songVibeTag(song);
    if (songVibe == targetVibe) return 1.0;

    // Partial affinity map — similar vibes score 0.6 instead of 0
    const affinity = <String, List<String>>{
      // Core relaxed spectrum
      'chill':        ['mellow', 'serene', 'dreamy', 'atmospheric', 'ethereal'],
      'mellow':       ['chill', 'serene', 'soulful', 'smooth'],
      'serene':       ['chill', 'mellow', 'ambient', 'ethereal'],

      // Emotional spectrum
      'emotional':    ['melancholic', 'romantic', 'soulful'],
      'melancholic':  ['emotional', 'soulful', 'dreamy'],
      'romantic':     ['emotional', 'smooth', 'soulful'],
      'soulful':      ['smooth', 'mellow', 'emotional'],
      'smooth':       ['soulful', 'romantic', 'mellow'],

      // Energy spectrum
      'energetic':    ['hype', 'electric', 'intense', 'upbeat'],
      'hype':         ['energetic', 'electric', 'party'],
      'intense':      ['energetic', 'aggressive', 'epic'],
      'aggressive':   ['intense', 'gritty'],
      'gritty':       ['aggressive', 'hype'],

      // Bright / positive
      'upbeat':       ['energetic', 'playful', 'groovy'],
      'playful':      ['upbeat', 'funky'],
      'groovy':       ['funky', 'upbeat'],
      'funky':        ['groovy', 'playful'],

      // Electronic / spatial
      'electric':     ['energetic', 'party', 'atmospheric'],
      'party':        ['hype', 'electric', 'upbeat'],
      'atmospheric':  ['dreamy', 'ethereal', 'cinematic', 'chill'],
      'ethereal':     ['dreamy', 'atmospheric', 'serene'],
      'dreamy':       ['chill', 'ethereal', 'melancholic'],

      // Cinematic / grand
      'cinematic':    ['epic', 'atmospheric'],
      'epic':         ['cinematic', 'intense'],

      // Focus / structure
      'focused':      ['serene', 'chill'],

      // Positive / uplifting
      'uplifting':    ['upbeat', 'emotional'],
    };
    final related = affinity[targetVibe] ?? [];
    return related.contains(songVibe) ? 0.6 : 0.1;
  }

  /// Refined Hybrid Discovery Algo
  List<Song> _curateByScore(List<Song> candidates, String targetVibe,
      {String targetGenre = '', int limit = 20, bool isAi = false}) {
    final now = DateTime.now();
    final maxPlays = candidates.fold<int>(1, (m, s) => s.playCount > m ? s.playCount : m);

    final scored = candidates.map((song) {
      final playScore = song.playCount / maxPlays;
      double freshScore = 0.0;
      if (song.lastPlayedAt != null) {
        final daysAgo = now.difference(song.lastPlayedAt!).inDays;
        freshScore = (1.0 - (daysAgo / 30.0)).clamp(0.0, 1.0);
      }

      final moodScore = _vibeMatchScore(song, targetVibe);
      final isExactGenre = targetGenre.isNotEmpty &&
          song.genre.toLowerCase().contains(targetGenre.toLowerCase());

      double total;
      if (isAi) {
        // AI AGGRESSIVE HYBRID (Discovery-focused)
        // 20% Genre Anchor, 60% Vibe Match, 20% Habits (Play + Fresh)
        total = (isExactGenre ? 0.20 : 0.0) +
            (moodScore * 0.60) +
            ((playScore * 0.10) + (freshScore * 0.10));

        // Add tiny deterministic noise based on Song ID to prevent identical ties
        final noise = (song.id % 100) / 1000.0;
        total += noise;
      } else {
        // ALGO STANDARD (Loyalty-focused)
        // Strictly Genre match is implicitly 1.0 because 'candidates' are genre-filtered
        total = (moodScore * 0.1) + (playScore * 0.5) + (freshScore * 0.4);
      }
      return MapEntry(song, total);
    }).toList();

    // Sort by score
    scored.sort((a, b) => b.value.compareTo(a.value));

    if (isAi) {
      // For AI: Take the top 3x candidates and pick 'limit' randomly from them
      // This ensures the AI isn't just a static re-sort of the Algo list.
      final pool = scored.take(limit * 3).map((e) => e.key).toList();
      if (pool.length > limit) {
        pool.shuffle();
        return pool.take(limit).toList();
      }
    }

    return scored.take(limit).map((e) => e.key).toList();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _normalizeGenre(String g) => g
      .trim()
      .split(' ')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  Future<void> _savePlaylistsToCache() async {
    if (_cachedPlaylists == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> data = _cachedPlaylists!.map((p) => {
        'name': p.name,
        'songIds': p.songs.map((s) => s.id).toList(),
        'isAi': p.isAiGenerated,
      }).toList();
      await prefs.setString(_playlistCachePref, jsonEncode(data));
      await prefs.setString(_playlistUpdatePref, _lastPlaylistUpdate!.toIso8601String());
    } catch (e) {
      print('[LLM] Failed to save playlist cache: $e');
    }
  }

  Future<void> _loadPlaylistsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_playlistCachePref);
      final dateStr = prefs.getString(_playlistUpdatePref);
      if (json == null || dateStr == null) return;

      final List<dynamic> list = jsonDecode(json);
      final List<SmartPlaylistData> result = [];
      for (var item in list) {
        final List<int> ids = List<int>.from(item['songIds']);
        final List<Song> songs = [];
        for (final id in ids) {
          final s = await DbService.instance.songs.get(id);
          if (s != null) songs.add(s);
        }
        if (songs.isNotEmpty) {
          result.add(SmartPlaylistData(
            name: item['name'],
            songs: songs,
            isAiGenerated: item['isAi'] ?? false,
          ));
        }
      }
      _cachedPlaylists = result;
      _lastPlaylistUpdate = DateTime.parse(dateStr);
      print('[LLM] Loaded ${result.length} playlists from cache');
    } catch (e) {
      print('[LLM] Failed to load playlist cache: $e');
    }
  }

  Future<void> checkAndAutoGenerateMonthlyRecap() async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final dayAfterTomorrow = now.add(const Duration(days: 2));
    final isDayBeforeLast = dayAfterTomorrow.month != now.month && tomorrow.month == now.month;
    final isLastDay = tomorrow.month != now.month;

    if (!isDayBeforeLast && !isLastDay) return;

    final monthLabel = _getMonthLabel(now);
    final exists = await DbService.instance.wrappedReports
        .filter()
        .periodLabelEqualTo(monthLabel)
        .findFirst();

    if (exists != null && exists.llmRecap.isNotEmpty) return;
    print('[LLM] Performing end-of-month auto-generation for $monthLabel...');
  }

  String _getMonthLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  /// Activity hint from current hour — used to prime the vibe selection.
  String _activityHintFromHour() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 9)   return 'during their morning routine';
    if (h >= 9 && h < 12)  return 'while working or studying';
    if (h >= 12 && h < 14) return 'on a lunch break';
    if (h >= 14 && h < 17) return 'during an afternoon grind';
    if (h >= 17 && h < 20) return 'winding down after work';
    if (h >= 20 && h < 23) return 'relaxing in the evening';
    return 'late at night';
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Generate a Wrapped recap paragraph.
  Future<String> generateWrappedRecap(WrappedReport report) async {
    if (_isAiEnabled && !_modelLoaded) {
      await loadModel();
    }
    await _loadFuture;
    generationProgress.value = 0;

    if (report.llmRecap.isNotEmpty) {
      print('[LLM] Using cached recap for ${report.periodLabel}');
      return report.llmRecap;
    }

    String? lyricsSnippet;
    try {
      final db = DbService.instance;
      final song = await db.songs
          .filter()
          .titleEqualTo(report.topSong)
          .isHiddenEqualTo(false)
          .findFirst();
      if (song != null) {
        final lyrics = await LyricsService.instance.fetchLyrics(song);
        if (lyrics != null && lyrics.isNotEmpty) {
          lyricsSnippet = lyrics.replaceAll(RegExp(r'\[.*?\]'), ' ').trim();
          if (lyricsSnippet.length > 150) lyricsSnippet = lyricsSnippet.substring(0, 150);
        }
      }
    } catch (_) {}

    final prompt = _buildRecapPrompt(report, lyricsSnippet);

    // 1. Try Local GGUF
    // Ensure we are truly ready if AI is enabled and model is available
    if (_isAiEnabled && _modelAvailable) {
      // If still loading, wait up to 15 more seconds specifically for the model
      int retry = 0;
      while (!_modelLoaded && retry < 30 && isModelLoading.value) {
        await Future.delayed(const Duration(milliseconds: 500));
        retry++;
      }
    }

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        modelStatus.value = 'AI: Generating recap on-device...';
        print('[LLM] Generating recap via Local GGUF...');
        if (!_modelLoaded || _llama == null) return _generateLocal(report);

        final stream = _llama!.generate(prompt: prompt, maxTokens: 80);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
          generationProgress.value++;
        }

        if (response.isNotEmpty) {
          final cleaned = _cleanLlmResponse(response);
          if (cleaned.length > 20) return _saveAndReturnRecap(report, cleaned);
        }
      } catch (e) {
        print('[LLM] Local recap error: $e');
      }
    }

    // 2. Try Gemini API
    final apiKey = await currentApiKey;
    if (apiKey.isNotEmpty) {
      try {
        modelStatus.value = 'AI: Calling Gemini API...';
        print('[LLM] Generating recap via Gemini API...');
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=$apiKey');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': _buildRecapPromptRaw(report, lyricsSnippet)}
                ]
              }
            ],
            'generationConfig': {'maxOutputTokens': 80, 'temperature': 0.7}
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final text =
              data['candidates'][0]['content']['parts'][0]['text'] as String;
          return _saveAndReturnRecap(report, text.trim());
        }
      } catch (e) {
        print('[LLM] Gemini recap error: $e');
      }
    }

    // 3. Template fallback
    print('[LLM] Falling back to templates.');
    report.isAiGenerated = false;
    await DbService.instance.isar.writeTxn(() async {
      await DbService.instance.wrappedReports.put(report);
    });
    
    final finalResult = await _generateLocal(report);
    if (_modelLoaded) {
      Future.delayed(const Duration(seconds: 10), () => disposeModel());
    }
    return finalResult;
  }

  // ── RECAP PROMPTS ─────────────────────────────────────────────────────────

  /// Prompt for local tiny LLMs — personality-first, fact-light.
  String _buildRecapPrompt(WrappedReport report, String? lyricsSnippet) {
    final topGenre = _getTopGenre(report);
    final loyalty = report.topArtistPlays > 50
        ? 'obsessively'
        : report.topArtistPlays > 20
            ? 'deeply'
            : 'consistently';
    final timeVibe = _peakHourVibe(_parsePeakHour(report.peakHourLabel));

    final instruction =
        'You are a snarky music personality writing a 2-sentence vibe check '
        'about a listener. Capture their soul, not their stats. '
        'They are $loyalty into $topGenre, a $timeVibe listener, '
        'and their spirit animal right now is ${report.topArtist}. '
        'Be punchy, poetic, second-person. No numbers. No lists.';

    return _wrapPrompt(instruction, 'You are the type of person who');
  }

  /// Plain instruction for Gemini (cloud API handles longer prompts fine).
  String _buildRecapPromptRaw(WrappedReport report, String? lyricsSnippet) {
    final topGenre = _getTopGenre(report);
    final loyalty = report.topArtistPlays > 50
        ? 'obsessively'
        : report.topArtistPlays > 20
            ? 'deeply'
            : 'consistently';
    final timeVibe = _peakHourVibe(_parsePeakHour(report.peakHourLabel));

    return 'Write a 2-sentence music personality vibe-check for ${report.periodLabel}. '
        'Speak directly to the listener in second person. '
        'They are $loyalty into $topGenre music. '
        'They are a $timeVibe listener whose current obsession is ${report.topArtist}. '
        'Do NOT list stats or numbers. Capture the *feeling* and personality — '
        'like a witty horoscope for a music lover. '
        '${lyricsSnippet != null ? 'Optional flavour from their top song: "$lyricsSnippet" — weave the mood in subtly, never quote it.' : ''} '
        'Output only the 2 sentences.';
  }

  /// Maps a peak hour int → a human vibe string for use in prompts.
  String _peakHourVibe(int hour) {
    if (hour >= 0 && hour < 5) return 'deep-night insomniac';
    if (hour >= 5 && hour < 9) return 'early-morning ritual';
    if (hour >= 9 && hour < 12) return 'focused midmorning';
    if (hour >= 12 && hour < 15) return 'lunch-hour escape';
    if (hour >= 15 && hour < 18) return 'late-afternoon grind';
    if (hour >= 18 && hour < 21) return 'golden-hour wind-down';
    return 'late-night overthinker';
  }

  /// Parse a peakHourLabel like "11pm" or "12am" back to an int (0–23).
  int _parsePeakHour(String label) {
    try {
      final lower = label.toLowerCase().trim();
      final isAm = lower.contains('am');
      final numStr = lower.replaceAll(RegExp(r'[^0-9]'), '');
      if (numStr.isEmpty) return 0;
      final num = int.parse(numStr);
      if (isAm) return num == 12 ? 0 : num;
      return num == 12 ? 12 : num + 12;
    } catch (_) {
      return 0;
    }
  }

  Future<String> _saveAndReturnRecap(WrappedReport report, String result) async {
    print('[LLM] Recap saved!');
    report.llmRecap = result;
    report.isAiGenerated = true;
    await DbService.instance.isar.writeTxn(() async {
      await DbService.instance.wrappedReports.put(report);
    });
    if (_isAiEnabled) {
      modelStatus.value = 'AI: Wrapped generation complete!';
    }
    if (_modelLoaded) {
      Future.delayed(const Duration(seconds: 10), () => disposeModel());
    }
    return result;
  }

  // ── SMART PLAYLISTS ───────────────────────────────────────────────────────

  Future<List<SmartPlaylistData>> generateSmartPlaylists() async {
    print('[LLM] generateSmartPlaylists() called');
    
    if (_isAiEnabled && !_modelLoaded) {
      await loadModel();
    }
    // Ensure we wait for any pending model load if AI is enabled
    if (_isAiEnabled && _loadFuture != null) {
      await _loadFuture;
    }

    // 1. Try Memory Cache
    if (_cachedPlaylists != null &&
        _lastPlaylistUpdate != null &&
        _isSameDay(_lastPlaylistUpdate!, DateTime.now())) {
      print('[LLM] Returning memory cached playlists');
      return _cachedPlaylists!;
    }

    // 2. Try Disk Cache
    if (_cachedPlaylists == null) {
      await _loadPlaylistsFromCache();
      if (_cachedPlaylists != null &&
          _lastPlaylistUpdate != null &&
          _isSameDay(_lastPlaylistUpdate!, DateTime.now())) {
        print('[LLM] Returning disk cached playlists');
        return _cachedPlaylists!;
      }
    }

    // 3. True Generation
    final db = DbService.instance;
    final allSongs =
        await db.songs.where().filter().isHiddenEqualTo(false).findAll();
    if (allSongs.isEmpty) {
      print('[LLM] No songs found for curation');
      return [];
    }

    print('[LLM] Curation started for ${allSongs.length} songs');
    final genreMap = <String, List<Song>>{};
    for (var s in allSongs) {
      final normalizedGenre = _normalizeGenre(s.genre);
      if (normalizedGenre.isNotEmpty) {
        genreMap.putIfAbsent(normalizedGenre, () => []).add(s);
      }
    }

    final sortedGenres = genreMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    final List<SmartPlaylistData> result = [];
    const fallbackNames = {
      'Pop': 'Top Hits',
      'Rock': 'Rock Caviar',
      'Rap': 'RapCaviar',
      'Jazz': 'Blue Note',
      'Classical': 'Grand Hall'
    };

    final activityHint = _activityHintFromHour();

    // Loop top 5 genres
    for (var i = 0; i < sortedGenres.length && i < 5; i++) {
      final genre = sortedGenres[i].key;
      final genreSongs = sortedGenres[i].value;
      if (genreSongs.length < 3) continue;

      // Attempt AI/Algo Hybrid — Discovery Engine
      bool aiWorked = false;
      if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
        try {
          generationProgress.value = 0;
          modelStatus.value = 'AI: Curating $genre session...';

          final vibeTag = await _askLlmForVibeTag(genre, activityHint);
          if (vibeTag.isNotEmpty) {
            final dynamicLimit = 15 + (DateTime.now().millisecond % 16);
            final aiSongs = _curateByScore(allSongs, vibeTag, targetGenre: genre, limit: dynamicLimit, isAi: true);
            final aiName = await _generateAiPlaylistName(genre, vibeTag);
            
            if (aiName.isNotEmpty && aiSongs.isNotEmpty) {
              result.add(SmartPlaylistData(name: aiName, songs: aiSongs, isAiGenerated: true));
              aiWorked = true;
            }
          }
        } catch (e) {
          print('[LLM] AI curation error: $e');
        }
      }

      // Fallback: ALGO playlist — strictly genre-locked
      if (!aiWorked) {
        final algoSongs = _curateByScore(genreSongs, '', limit: 20);
        result.add(SmartPlaylistData(
          name: fallbackNames[genre] ?? '$genre Vibes',
          songs: algoSongs,
          isAiGenerated: false,
        ));
      }
    }

    // ── Final Mixed Fallback ──
    if (result.length < 2 && allSongs.isNotEmpty) {
      final mixed = List<Song>.from(allSongs)..shuffle();
      result.add(SmartPlaylistData(
        name: 'The Daily Mix: Reloaded',
        songs: mixed.take(20).toList(),
        isAiGenerated: false,
      ));
    }

    _cachedPlaylists = result;
    _lastPlaylistUpdate = DateTime.now();
    
    // Only save to disk cache if we actually had a model ready or AI is disabled.
    // This prevents "failing upward" and caching non-AI playlists when the model was just slow to load.
    if (!_isAiEnabled || _modelLoaded) {
      await _savePlaylistsToCache();
    }

    if (_modelLoaded) {
      Future.delayed(const Duration(seconds: 10), () => disposeModel());
    }

    return result;
  }

  String _randomColorHex() {
    const colors = ['#1DB954', '#8E44AD', '#E74C3C', '#E8821A', '#2C3E50', '#1A3A5C', '#2D6A4F', '#5C4A1E'];
    return colors[DateTime.now().millisecond % colors.length];
  }

  /// Asks the LLM for a playlist name given genre + vibe context.
  Future<String> _generateAiPlaylistName(String genre, String vibe) async {
    if (!_modelAvailable || !_modelLoaded || _llama == null || !_isAiEnabled) return '';

    final vibeHint = vibe.isNotEmpty ? ' with a $vibe feeling' : '';
    final instruction =
        'Give exactly two English words as a creative name for a $genre playlist$vibeHint. '
        'The words must evoke the mood, not describe it literally. '
        'Output only the two words, nothing else.';
    final prompt = _wrapPrompt(instruction, 'Name:');

    try {
      if (!_modelLoaded || _llama == null) return '';
      final stream = _llama!.generate(prompt: prompt, maxTokens: 8);
      String response = '';
      await for (final token in stream) {
        if (!_modelLoaded || _llama == null) break;
        response += token;
        generationProgress.value++;
      }
      return response.isNotEmpty ? _cleanPlaylistName(response) : '';
    } catch (_) {
      return '';
    }
  }

  Future<MapEntry<Song, String>?> generateNextVibeSong(Song currentSong) async {
    await _loadFuture;

    final db = DbService.instance;
    final allSongs =
        await db.songs.where().filter().isHiddenEqualTo(false).findAll();
    if (allSongs.isEmpty) return null;

    final currentVibe = _songVibeTag(currentSong);
    var candidates = allSongs.where((s) => s.id != currentSong.id).toList();
    if (candidates.isEmpty) return null;

    final scored = _curateByScore(candidates, currentVibe, limit: 10);
    final nextSong = scored.isNotEmpty ? scored.first : candidates.first;

    String transition = "Up next: ${nextSong.title}";

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        final instruction =
            'You are a DJ. Write one short sentence transitioning from "${currentSong.title}" to "${nextSong.title}". Be cool and brief.';
        final prompt = _wrapPrompt(instruction, 'Up next —');

        if (!_modelLoaded || _llama == null) {
          return MapEntry(nextSong, "Next up: ${nextSong.title}");
        }

        final stream = _llama!.generate(prompt: prompt, maxTokens: 40);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
        }

        if (response.isNotEmpty) {
          transition = _cleanLlmResponse(response);
          print('[LLM] DJ Intro: $transition');
        }
      } catch (e) {
        print('[LLM] AI DJ error: $e');
      }
    } else {
      final templates = [
        "Keeping the vibes flowing, here's ${nextSong.title} by ${nextSong.artist}.",
        "That was ${currentSong.title}. Now let's jump into ${nextSong.title}.",
        "You're locked in. Up next is ${nextSong.artist} with ${nextSong.title}.",
        "Don't touch that dial, we're jumping straight into ${nextSong.title}.",
        "Next track coming right up: ${nextSong.title}."
      ];
      templates.shuffle();
      transition = templates.first;
    }

    return MapEntry(nextSong, transition);
  }

  // ── Personality & Slide Insights ──────────────────────────────────────────

  /// Dedicated cleaner for playlist names: strictly 2 words, title-cased, alpha only.
  String _cleanPlaylistName(String text) {
    if (text.isEmpty) return '';

    String s = text
        .replaceAll(RegExp(r'\[\/?INST[\]\}]', caseSensitive: false), '')
        .replaceAll(RegExp(r'<s>|</s>|<start_of_turn>|<end_of_turn>', caseSensitive: false), '')
        .replaceAll(RegExp(r'###\s*(INSTRUCTION|RESPONSE|END)[^:\n]*:?', caseSensitive: false), '')
        .replaceAll(RegExp(r'Name\s*:', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'(playlist|genre|word|name|music|creative|catchy|here|sure|certainly)[^a-zA-Z]*',
                caseSensitive: false), '')
        .trim();

    final firstLine =
        s.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');

    final words = firstLine.trim().split(RegExp(r'\s+'));
    final validWords = <String>[];

    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (clean.length >= 2 && !_isJunkWord(clean.toLowerCase())) {
        validWords.add(clean[0].toUpperCase() + clean.substring(1).toLowerCase());
        if (validWords.length == 2) break;
      }
    }

    if (validWords.isNotEmpty) {
      return validWords.join(' ');
    }
    return '';
  }

  /// 'new' removed — it kills valid names like "New Wave", "New Soul".
  bool _isJunkWord(String w) {
    const junk = {
      'the', 'and', 'for', 'that', 'this', 'with', 'from', 'just', 'only',
      'here', 'sure', 'okay', 'well', 'yes', 'out', 'one',
    };
    return junk.contains(w);
  }

  /// Cleans general LLM response — used for recaps, insights, DJ intros.
  String _cleanLlmResponse(String text, {bool isTitle = false}) {
    if (text.isEmpty) return '';

    String scrubbed = text
        .replaceAll(RegExp(r'\[\/?INST[\]\}]', caseSensitive: false), '')
        .replaceAll(RegExp(r'<s>|</s>|<start_of_turn>|<end_of_turn>', caseSensitive: false), '')
        .replaceAll(RegExp(r'###\s*(INSTRUCTION|RESPONSE|END)[^:\n]*:?', caseSensitive: false), '')
        .trim();

    final lines = scrubbed.split('\n');
    String result = '';

    for (var line in lines) {
      String l = line.trim();
      if (l.isEmpty) continue;

      while (l.startsWith(':') || l.startsWith('-') || l.startsWith(' ')) {
        l = l.substring(1).trim();
      }

      final low = l.toLowerCase();
      if (low.contains('playlist should') ||
          low.contains('style should') ||
          low.contains('based on your')) continue;
      if (low.contains('here is') ||
          low.contains('here\'s') ||
          low.contains('sure, i can')) continue;
      if (low.contains('certainly') ||
          low.contains('submission') ||
          low.contains('instruction')) continue;
      if (low.contains('write a short') ||
          low.contains('create a new word') ||
          low.contains('return only')) continue;
      if (low.contains('give one') ||
          low.contains('single english') ||
          low.contains('output only')) continue;
      if (low.contains('top genre:') ||
          low.contains('peak hour:') ||
          low.contains('top artist:') ||
          low.contains('top song:')) continue;
      if (low.contains('playlist name:') ||
          low.contains('name:') ||
          low.contains('response:')) continue;
      if (low.startsWith('user:') ||
          low.startsWith('assistant:') ||
          low.startsWith('system:') ||
          low.startsWith('model:')) continue;
      if (low.contains('<start_of_turn>') ||
          low.contains('<end_of_turn>')) continue;

      if (isTitle) {
        final words = l.split(RegExp(r'\s+'));
        if (words.isNotEmpty) {
          final first = words.first.replaceAll(RegExp(r'[^a-zA-Z]'), '');
          if (first.length < 2 ||
              first.toLowerCase() == 'playlist' ||
              first.toLowerCase() == 'name') {
            if (words.length > 1) {
              l = words.skip(1).join(' ');
            } else {
              continue;
            }
          }
        }
        l = l.split(' ').take(3).join(' ');
      }

      result = l;
      break;
    }

    if (result.isEmpty) result = scrubbed.split('\n').first.trim();

    result = result.replaceAll('"', '').replaceAll('\'', '');
    if (result.endsWith(':') || result.endsWith('.')) {
      if (result.split(' ').length < 5) {
        result = result.substring(0, result.length - 1);
      }
    }

    return result;
  }

  // ── PERSONALITY TITLE ─────────────────────────────────────────────────────
  //
  // FIX: The old prompt used _wrapPrompt(instruction, 'The') which caused both
  // Gemma-3-1B and Llama-3.2-1B to write a sentence ("The listener is a devoted
  // Pop fan...") instead of a 2-word name. 1B models cannot handle two conflicting
  // signals at once — "output only 2 words" (rule) vs "The" (sentence primer).
  // The sentence primer always wins at this scale.
  //
  // Fix applied:
  //   1. Instruction uses example-pattern prompting instead of abstract rules.
  //      Examples do far more than rules on sub-2B models.
  //   2. Prefix changed to 'The ' (trailing space) — lands the model directly
  //      at the adjective slot with no ambiguity.
  //   3. Early-exit breaks the stream the moment we have 2 words, preventing
  //      sentence drift even when generation wants to continue.
  //   4. Dedicated _cleanPersonalityTitle strips any continuation and enforces
  //      exactly 2 alpha words, min 3 chars each.

  /// Generate a unique personality title (e.g. "The Velvet Midnight")
  Future<String> generateListeningPersonality(WrappedReport report) async {
    await _loadFuture;
    final topGenre = _getTopGenre(report);
    final timeVibe = _peakHourVibe(_parsePeakHour(report.peakHourLabel));
    final loyalty = report.topArtistPlays > 50
        ? 'obsessive'
        : report.topArtistPlays > 20
            ? 'devoted'
            : 'casual';

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        if (!_modelLoaded || _llama == null) return _personalityFallback(topGenre);

        // Pattern-completion prompt — examples beat abstract rules on 1B models.
        // Prefix 'The ' puts model directly at the adjective slot.
        final instruction =
            'Create a unique music listener title with ONE adjective and ONE noun. '
            'Avoid generic terms like "Nomad" or "Listener". '
            'Genre: $topGenre. Mood: $timeVibe. Loyalty: $loyalty. '
            'Examples: "Velvet Midnight", "Static Dreamer", "Neon Specter", "Hollow Echo", "Glass Wanderer". '
            'Output ONLY the two words after "The".';

        final prompt = _wrapPrompt(instruction, 'The ');

        generationProgress.value = 0;
        final stream = _llama!.generate(prompt: prompt, maxTokens: 8);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
          generationProgress.value++;
          // Early-exit: stop as soon as we have 2 words — prevents sentence drift
          if (response.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length >= 2) break;
        }

        if (response.isNotEmpty) {
          final cleaned = _cleanPersonalityTitle(response);
          if (cleaned.length > 3) return 'The $cleaned';
        }
      } catch (_) {}
    }

    return _personalityFallback(topGenre);
  }

  /// Dedicated cleaner for personality titles.
  /// Extracts exactly 2 title-cased alpha words, strips any sentence continuation.
  String _cleanPersonalityTitle(String text) {
    if (text.isEmpty) return '';

    String s = text
        .replaceAll(RegExp(r'\[\/?INST[\]\}]', caseSensitive: false), '')
        .replaceAll(RegExp(r'<s>|</s>|<start_of_turn>|<end_of_turn>', caseSensitive: false), '')
        .replaceAll(RegExp(r'###\s*(INSTRUCTION|RESPONSE|END)[^:\n]*:?', caseSensitive: false), '')
        // Strip echoed "The" prefix if model repeated it
        .replaceAll(RegExp(r'^[Tt]he\s+', caseSensitive: false), '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    // Take only the first line — ignore any sentence drift after newline
    s = s.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();

    // Pull exactly 2 valid alpha words, min 3 chars each, skip junk
    final words = s.split(RegExp(r'\s+'));
    final valid = <String>[];
    for (final w in words) {
      final clean = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (clean.length >= 3 && !_isJunkWord(clean.toLowerCase())) {
        valid.add(clean[0].toUpperCase() + clean.substring(1).toLowerCase());
        if (valid.length == 2) break;
      }
    }

    return valid.join(' ');
  }

  /// Algo fallback map for personality titles — covers all genre additions.
  String _personalityFallback(String topGenre) {
    final g = topGenre.toLowerCase();
    if (g.contains('lo-fi') || g.contains('chill') || g.contains('ambient')) return 'The Tranquil Soul';
    if (g.contains('rock') || g.contains('metal') || g.contains('punk')) return 'The Sonic Rebel';
    if (g.contains('pop')) return 'The Chart Chaser';
    if (g.contains('hip hop') || g.contains('rap') || g.contains('trap')) return 'The Frequency Rider';
    if (g.contains('jazz') || g.contains('blues')) return 'The Midnight Wanderer';
    if (g.contains('electronic') || g.contains('techno') || g.contains('house')) return 'The Neon Pulse';
    if (g.contains('r&b') || g.contains('soul') || g.contains('funk')) return 'The Velvet Groove';
    if (g.contains('classical') || g.contains('orchestral') || g.contains('piano')) return 'The Grand Listener';
    if (g.contains('worship') || g.contains('gospel') || g.contains('christian')) return 'The Spirit Seeker';
    if (g.contains('indie') || g.contains('alt')) return 'The Quiet Dreamer';
    if (g.contains('drill')) return 'The Street Poet';
    if (g.contains('acoustic') || g.contains('folk') || g.contains('country')) return 'The Honest Drifter';
    if (g.contains('k-pop') || g.contains('j-pop')) return 'The Global Fanatic';
    if (g.contains('dance')) return 'The Rhythm Reactor';
    
    // Final fallback — randomize slightly to avoid "stuck" feeling
    final defaults = ['The Melodic Nomad', 'The Rhythm Voyager', 'The Sonic Architect', 'The Audio Alchemist'];
    return defaults[DateTime.now().millisecond % defaults.length];
  }

  /// Generate a catchy insight about peak listening time
  Future<String> generateTimeInsight(int peakHour, int totalMinutes) async {
    await _loadFuture;
    final timeStr = peakHour >= 12
        ? '${peakHour == 12 ? 12 : peakHour - 12} PM'
        : '${peakHour == 0 ? 12 : peakHour} AM';

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        if (!_modelLoaded || _llama == null) {
          return '$timeStr — the perfect hour for music.';
        }

        final instruction =
            'Write one short witty sentence about listening to music at $timeStr. Max 12 words. No quotes.';
        final prompt = _wrapPrompt(instruction, '$timeStr —');

        final stream = _llama!.generate(prompt: prompt, maxTokens: 24);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
        }
        if (response.isNotEmpty) {
          final c = _cleanLlmResponse(response);
          if (c.length > 5) return '$timeStr — $c';
        }
      } catch (_) {}
    }

    if (peakHour >= 22 || peakHour <= 4) return '$timeStr — Late nights hit different.';
    if (peakHour >= 7 && peakHour <= 10) return '$timeStr — Fueling your morning with pure sound.';
    return '$timeStr — When the world fades and the music takes over.';
  }

  /// Generate a witty remark about the top artist
  Future<String> generateArtistInsight(String artist, int playCount) async {
    await _loadFuture;

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        if (!_modelLoaded || _llama == null) {
          return '$artist was there for you. Every single time.';
        }

        final instruction =
            'Write one cheeky 10-word sentence about $artist being my most played artist. No quotes.';
        final prompt = _wrapPrompt(instruction, '$artist');

        final stream = _llama!.generate(prompt: prompt, maxTokens: 24);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
        }
        if (response.isNotEmpty) {
          final c = _cleanLlmResponse(response);
          if (c.length > 5) return c;
        }
      } catch (_) {}
    }

    return '$artist was there for you. All $playCount times.';
  }

  /// Generate a witty remark about total minutes
  Future<String> generateMinutesInsight(int minutes) async {
    await _loadFuture;
    final hours = (minutes / 60).toStringAsFixed(1);

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        if (!_modelLoaded || _llama == null) {
          return 'That\'s $hours hours. Your headphones deserve a raise.';
        }

        final instruction =
            'Write one funny 12-word sentence about listening to $hours hours of music. No quotes.';
        final prompt = _wrapPrompt(instruction, 'That\'s');

        final stream = _llama!.generate(prompt: prompt, maxTokens: 28);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
        }
        if (response.isNotEmpty) {
          final c = _cleanLlmResponse(response);
          if (c.length > 5) return c;
        }
      } catch (_) {}
    }

    return 'That\'s $hours hours. We\'re not judging. (Okay, maybe a little).';
  }

  /// Generate a witty caption for the top song
  Future<String> generateSongInsight(String song) async {
    await _loadFuture;

    if (_modelAvailable && _modelLoaded && _llama != null && _isAiEnabled) {
      try {
        if (!_modelLoaded || _llama == null) return 'Your soundtrack, on loop.';

        final instruction =
            'Write one punchy 8-word caption for "$song" being my most played song. No quotes.';
        final prompt = _wrapPrompt(instruction, '"$song" —');

        final stream = _llama!.generate(prompt: prompt, maxTokens: 20);
        String response = '';
        await for (final token in stream) {
          if (!_modelLoaded || _llama == null) break;
          response += token;
        }
        if (response.isNotEmpty) {
          final c = _cleanLlmResponse(response, isTitle: true);
          if (c.length > 5) return c;
        }
      } catch (_) {}
    }

    return 'Your soundtrack, on loop.';
  }

  // ── Local template-based fallback ─────────────────────────────────────────

  String _generateLocal(WrappedReport report) {
    final templates = [
      'You had a cinematic ${report.periodLabel}. '
          '${report.topArtist} carried you through the best and worst moments '
          'with ${report.topArtistPlays} plays. '
          'Your ${report.personalityType} energy peaked at ${report.peakHourLabel} — '
          "and honestly? We stan the dedication.",

      '${report.periodLabel} was YOUR era. '
          '${report.topArtist} was on repeat (${report.topArtistPlays} times, no shame). '
          'You vibed hardest at ${report.peakHourLabel}. '
          '${report.streakDays}-day streak? That\'s called commitment.',

      'Let\'s talk about your ${report.periodLabel}. '
          '${report.topArtist} dominated your ears — ${report.topArtistPlays} plays strong. '
          'Peak hours: ${report.peakHourLabel}. '
          'Personality: ${report.personalityType}. Verdict: immaculate taste.',

      '${report.totalMinutes} minutes of pure emotion this ${report.periodLabel}. '
          '${report.topArtist} was your ride-or-die artist. '
          'You hit a ${report.streakDays}-day listening streak and peaked at ${report.peakHourLabel}. '
          'A ${report.personalityType} through and through.',

      'This ${report.periodLabel}, you didn\'t just listen - you felt it. '
          '${report.topArtist} led the soundtrack with ${report.topArtistPlays} plays. '
          'Your peak moment? ${report.peakHourLabel}. '
          '${report.personalityType} energy all the way.',

      'Main character energy detected this ${report.periodLabel}. '
          '${report.topArtist} was your go-to (${report.topArtistPlays} plays). '
          'You owned ${report.peakHourLabel} like it was your personal stage. '
          '${report.streakDays}-day streak? Icon behavior.',

      'Your ${report.periodLabel} was basically a curated playlist. '
          '${report.topArtist} took the spotlight with ${report.topArtistPlays} plays. '
          'Peak listening at ${report.peakHourLabel}, of course. '
          '${report.personalityType} mood = unmatched.',

      '${report.totalMinutes} minutes, zero skips (we assume). '
          '${report.topArtist} stayed on top with ${report.topArtistPlays} plays. '
          'You showed up most at ${report.peakHourLabel}. '
          '${report.streakDays}-day streak? Elite consistency.',

      'If this ${report.periodLabel} had a theme song, it was ${report.topArtist}. '
          '${report.topArtistPlays} plays says it all. '
          'You thrived at ${report.peakHourLabel} — peak vibes only. '
          '${report.personalityType} energy certified.',

      'You understood the assignment this ${report.periodLabel}. '
          '${report.topArtist} carried hard (${report.topArtistPlays} plays). '
          '${report.peakHourLabel} was your power hour. '
          'And that ${report.streakDays}-day streak? Respect.',

      'Your listening stats are telling a story this ${report.periodLabel}. '
          '${report.topArtist}: ${report.topArtistPlays} plays. '
          'Peak time: ${report.peakHourLabel}. '
          'Conclusion: ${report.personalityType} and thriving.',

      'No one was doing it like you this ${report.periodLabel}. '
          '${report.topArtist} dominated your queue (${report.topArtistPlays} plays). '
          'You peaked at ${report.peakHourLabel} — naturally. '
          '${report.streakDays}-day streak locked in.',

      'This ${report.periodLabel} was powered by vibes. '
          '${report.topArtist} delivered ${report.topArtistPlays} times. '
          'You showed up strongest at ${report.peakHourLabel}. '
          '${report.personalityType} energy never missed.',

      'A recap of your ${report.periodLabel}? Say less. '
          '${report.topArtist} on repeat (${report.topArtistPlays} plays). '
          '${report.peakHourLabel} was your golden hour. '
          '${report.streakDays}-day streak = no breaks, just vibes.',

      'You built a whole universe this ${report.periodLabel}. '
          '${report.topArtist} was the soundtrack (${report.topArtistPlays} plays). '
          'Peak listening at ${report.peakHourLabel}. '
          '${report.personalityType} aura: undeniable.',

      'Stats don\'t lie - this ${report.periodLabel} was iconic. '
          '${report.topArtist} led with ${report.topArtistPlays} plays. '
          '${report.peakHourLabel} was your moment. '
          '${report.streakDays}-day streak? Legendary behavior.',

      'This ${report.periodLabel}, you were in your feelings (and your playlist). '
          '${report.topArtist} led the charge with ${report.topArtistPlays} plays. '
          '${report.peakHourLabel} was your moment. No skips, just vibes.',

      'You really said "run it back" this ${report.periodLabel}. '
          '${report.topArtist} played ${report.topArtistPlays} times. '
          'Peak hour? ${report.peakHourLabel}. '
          'We see you.',

      'Your ${report.periodLabel} was powered by repetition. '
          '${report.topArtist} stayed undefeated (${report.topArtistPlays} plays). '
          '${report.streakDays}-day streak? That\'s discipline.',

      'Some people listened. You *committed* this ${report.periodLabel}. '
          '${report.topArtist} with ${report.topArtistPlays} plays says it all. '
          'Peak at ${report.peakHourLabel}.',

      'This ${report.periodLabel}, you found your loop and stayed in it. '
          '${report.topArtist} carried (${report.topArtistPlays} plays). '
          '${report.personalityType} energy, no doubt.',

      'Your music taste? Loud and clear this ${report.periodLabel}. '
          '${report.topArtist} dominated your plays (${report.topArtistPlays}). '
          '${report.peakHourLabel} was your peak zone.',

      'You had one mission this ${report.periodLabel}: vibes. '
          '${report.topArtist} delivered ${report.topArtistPlays} times. '
          '${report.streakDays}-day streak? Mission accomplished.',

      'Let\'s not pretend - ${report.topArtist} WAS your ${report.periodLabel}. '
          '${report.topArtistPlays} plays later, still iconic. '
          '${report.peakHourLabel} was your prime time.',

      'This ${report.periodLabel}, you pressed play and never looked back. '
          '${report.topArtist} stayed on repeat (${report.topArtistPlays} plays). '
          '${report.personalityType} mood locked in.',

      'You curated chaos this ${report.periodLabel}. '
          '${report.topArtist} led with ${report.topArtistPlays} plays. '
          '${report.peakHourLabel} was your peak energy window.',

      'If obsession had stats, this would be it. '
          '${report.topArtist}: ${report.topArtistPlays} plays this ${report.periodLabel}. '
          'No explanation needed.',

      'You really built a routine this ${report.periodLabel}. '
          '${report.topArtist} stayed on top (${report.topArtistPlays} plays). '
          '${report.streakDays}-day streak? Consistency wins.',

      'This ${report.periodLabel}, your headphones worked overtime. '
          '${report.totalMinutes} minutes and counting. '
          '${report.topArtist} carried the playlist.',

      'You unlocked a new level of listening this ${report.periodLabel}. '
          '${report.topArtist} hit ${report.topArtistPlays} plays. '
          '${report.peakHourLabel} = peak performance.',

      'No one was looping like you this ${report.periodLabel}. '
          '${report.topArtist} (${report.topArtistPlays} plays). '
          'That\'s dedication.',

      'Your ${report.periodLabel} had one rule: play it again. '
          '${report.topArtist} dominated your stats (${report.topArtistPlays} plays). '
          '${report.personalityType} energy stayed consistent.',

      'This ${report.periodLabel}, you trusted the algorithm — and yourself. '
          '${report.topArtist} came out on top (${report.topArtistPlays} plays). '
          '${report.peakHourLabel} was your zone.',

      'A quick recap of your ${report.periodLabel}: '
          '${report.topArtist}, ${report.topArtistPlays} plays, '
          '${report.streakDays}-day streak, and zero regrets.',

      'You stayed loyal this ${report.periodLabel}. '
          '${report.topArtist} led every session (${report.topArtistPlays} plays). '
          '${report.peakHourLabel}? Right on schedule.',

      'Your listening pattern this ${report.periodLabel}? Predictable — in the best way. '
          '${report.topArtist} stayed on repeat (${report.topArtistPlays}). '
          '${report.personalityType} energy confirmed.',

      'This ${report.periodLabel}, you didn\'t chase trends - you made habits. '
          '${report.topArtist} carried (${report.topArtistPlays} plays). '
          '${report.streakDays}-day streak locked in.',

      'You turned moments into music this ${report.periodLabel}. '
          '${report.topArtist} was there ${report.topArtistPlays} times. '
          '${report.peakHourLabel} hit different.',

      'Let\'s summarize your ${report.periodLabel}: '
          'repeat, repeat, repeat. '
          '${report.topArtist} with ${report.topArtistPlays} plays. Enough said.',

      'This ${report.periodLabel}, your playlist had a clear favorite. '
          '${report.topArtist} (${report.topArtistPlays} plays). '
          'No competition.',

      'You stayed in your zone this ${report.periodLabel}. '
          '${report.topArtist} led your stats (${report.topArtistPlays}). '
          '${report.peakHourLabel} was your comfort hour.',

      'You didn\'t switch it up - and it worked. '
          '${report.topArtist} dominated your ${report.periodLabel} (${report.topArtistPlays} plays). '
          '${report.personalityType} energy stayed strong.',
    ];

    final index = (report.totalMinutes + report.topArtistPlays) % templates.length;
    return templates[index];
  }

  String _getTopGenre(WrappedReport report) {
    try {
      final Map<String, dynamic> genres = jsonDecode(report.genreJsonStr);
      if (genres.isEmpty) return 'Unknown';
      var top = genres.entries.first;
      for (var e in genres.entries) {
        if ((e.value as num) > (top.value as num)) top = e;
      }
      return top.key;
    } catch (_) {
      return 'Unknown';
    }
  }
}