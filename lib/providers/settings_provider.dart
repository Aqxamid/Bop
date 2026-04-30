import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool aiEnabled;
  final bool gaplessPlayback;
  final int gaplessSeconds;

  SettingsState({
    this.aiEnabled = true,
    this.gaplessPlayback = false,
    this.gaplessSeconds = 2,
  });

  SettingsState copyWith({
    bool? aiEnabled,
    bool? gaplessPlayback,
    int? gaplessSeconds,
  }) {
    return SettingsState(
      aiEnabled: aiEnabled ?? this.aiEnabled,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      gaplessSeconds: gaplessSeconds ?? this.gaplessSeconds,
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      aiEnabled: prefs.getBool('llm_ai_enabled') ?? true,
      gaplessPlayback: prefs.getBool('gapless_playback') ?? false,
      gaplessSeconds: prefs.getInt('gapless_seconds') ?? 2,
    );
  }

  Future<void> setAiEnabled(bool enabled) async {
    state = state.copyWith(aiEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('llm_ai_enabled', enabled);
  }

  Future<void> setGaplessPlayback(bool enabled) async {
    state = state.copyWith(gaplessPlayback: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gapless_playback', enabled);
  }

  Future<void> setGaplessSeconds(int seconds) async {
    state = state.copyWith(gaplessSeconds: seconds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gapless_seconds', seconds);
  }
}
