// screens/profile/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/llm_service.dart';
import '../../services/lyrics_service.dart';
import '../../services/metadata_service.dart';
import '../../services/db_service.dart';
import '../../models/song.dart';
import 'package:isar/isar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/stats_provider.dart'; // For debugDateProvider + llmModelReadyProvider
import '../../services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _hasApiKey = false;
  String _modelFilename = 'None';
  bool _isModelLoading = false;
  bool _isPickingModel = false;

  String _username = 'Guest';
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _checkApiKey();
    _loadProfile();
    // Keep _modelFilename in sync whenever modelName notifier fires
    LlmService.instance.modelName.addListener(_onModelNameChanged);
  }

  @override
  void dispose() {
    LlmService.instance.modelName.removeListener(_onModelNameChanged);
    super.dispose();
  }

  void _onModelNameChanged() {
    if (!mounted) return;
    final name = LlmService.instance.modelName.value;
    setState(() {
      _modelFilename = (name != null && name.isNotEmpty) ? name : 'None';
    });
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      String? path = prefs.getString('avatar_path');
      // If the file was in cache and got deleted, clear it to prevent errors
      if (path != null && !File(path).existsSync()) {
        await prefs.remove('avatar_path');
        path = null;
      }

      setState(() {
        _username = prefs.getString('username') ?? 'Guest';
        _avatarPath = path;
      });
    }
  }

  void _checkApiKey() async {
    final key = await LlmService.instance.currentApiKey;
    final persistedName = LlmService.instance.modelName.value;
    final modelPath = await LlmService.instance.currentModelPath;

    if (mounted) {
      setState(() {
        _hasApiKey = key.isNotEmpty;
        if (persistedName != null && persistedName.isNotEmpty) {
          _modelFilename = persistedName;
        } else if (modelPath.isNotEmpty) {
          _modelFilename = modelPath.split('/').last.split('\\').last;
        } else {
          _modelFilename = 'None';
        }
      });
    }
  }

  void _pickModel() async {
    if (_isPickingModel) return;
    
    setState(() => _isPickingModel = true);
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any, // GGUF files often don't have a standard mime type
      );
      
      if (!mounted || result == null || result.files.single.path == null) {
        if (mounted) setState(() => _isPickingModel = false);
        return;
      }

      final path = result.files.single.path!;
      if (!path.toLowerCase().endsWith('.gguf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a valid .gguf model file.')),
          );
          setState(() => _isPickingModel = false);
        }
        return;
      }

      setState(() => _isModelLoading = true);
      try {
        await LlmService.instance.loadModel(path);
        if (!mounted) return;
        
        await LlmService.instance.updateModelPath(path);
        // Notify providers that model state changed
        ref.read(llmModelReadyProvider.notifier).state = LlmService.instance.isModelLoaded;
        ref.invalidate(aiPlaylistsProvider);
        _checkApiKey();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Model loaded successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          String message = e.toString().replaceAll('Exception: ', '');
          if (message.contains('ENOSPC')) {
            message = 'Error: Not enough storage space on device to import model.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(label: 'OK', onPressed: () {}),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isModelLoading = false;
            _isPickingModel = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPickingModel = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Picker error: $e')),
        );
      }
    }
  }

  void _showApiKeyDialog() async {
    final controller = TextEditingController(text: await LlmService.instance.currentApiKey);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Gemini API Key', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter API Key',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              await LlmService.instance.updateApiKey(controller.text.trim());
              _checkApiKey();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: BopTheme.green)),
          ),
        ],
      ),
    );
  }

  void _showLyricsDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool started = false;
        int current = 0;
        int total = 0;
        bool done = false;

        return StatefulBuilder(builder: (context, setDialogState) {
          if (!started) {
            started = true;
            LyricsService.instance.downloadAllMissingLyrics(
              onProgress: (c, t) {
                if (ctx.mounted) {
                  setDialogState(() {
                    current = c;
                    total = t;
                    if (t > 0 && c >= t) done = true;
                  });
                }
              },
            ).then((_) {
              if (ctx.mounted) {
                setDialogState(() => done = true);
              }
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF282828),
            title: const Text('Downloading Lyrics', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (total > 0) ...[
                  LinearProgressIndicator(
                    value: total == 0 ? 0 : current / total,
                    backgroundColor: Colors.white24,
                    color: BopTheme.green,
                  ),
                  const SizedBox(height: 16),
                  Text('$current / $total downloaded', style: const TextStyle(color: Colors.white70)),
                ] else if (done) ...[
                  const Text('All lyrics are up to date!', style: TextStyle(color: Colors.white70)),
                ] else ...[
                  const CircularProgressIndicator(color: BopTheme.green),
                  const SizedBox(height: 16),
                  const Text('Scanning library...', style: TextStyle(color: Colors.white70)),
                ],
              ],
            ),
            actions: [
              if (done || total == 0)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close', style: TextStyle(color: BopTheme.green)),
                ),
            ],
          );
        });
      },
    );
  }

  void _showEditProfileDialog() async {
    final controller = TextEditingController(text: _username);
    String? tempAvatar = _avatarPath;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    withData: true,
                  );
                  if (result != null) {
                    final file = result.files.single;
                    if (file.path != null) {
                      setDialogState(() => tempAvatar = file.path);
                    } else if (file.bytes != null) {
                      final tempDir = await getTemporaryDirectory();
                      final tempFile = File('${tempDir.path}/avatar_temp_${DateTime.now().millisecondsSinceEpoch}.png');
                      await tempFile.writeAsBytes(file.bytes!);
                      setDialogState(() => tempAvatar = tempFile.path);
                    }
                  }
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: BopTheme.surfaceAlt,
                  backgroundImage: tempAvatar != null ? FileImage(File(tempAvatar!)) : null,
                  child: tempAvatar == null ? const Icon(Icons.add_a_photo, color: Colors.white54) : null,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: 'Enter your name',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final newName = controller.text.trim().isNotEmpty ? controller.text.trim() : 'Guest';
                await prefs.setString('username', newName);
                
                if (tempAvatar != null && tempAvatar != _avatarPath) {
                  try {
                    final docDir = await getApplicationDocumentsDirectory();
                    final savePath = '${docDir.path}/avatar_user.png';
                    final oldFile = File(savePath);
                    if (await oldFile.exists()) await oldFile.delete();
                    await File(tempAvatar!).copy(savePath);
                    await prefs.setString('avatar_path', savePath);
                  } catch (e) {
                    print('Error saving avatar: $e');
                  }
                }
                
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save', style: TextStyle(color: BopTheme.green)),
            ),
          ],
        ),
      ),
    );
    _loadProfile();
  }

  Future<void> _fetchAllMissingMetadata() async {
    final songs = await DbService.instance.isar.songs.where().findAll();
    final missing = songs.where((s) => 
      MetadataService.instance.isArtistMissing(s.artist) || 
      MetadataService.instance.isAlbumMissing(s.album) || 
      MetadataService.instance.isGenreMissing(s.genre)
    ).toList();

    if (missing.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All songs already have metadata!')),
        );
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Fetching Metadata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(color: BopTheme.green),
            const SizedBox(height: 16),
            Text('Processing ${missing.length} songs...'),
          ],
        ),
      ),
    );

    int count = 0;
    for (final song in missing) {
      try {
        await MetadataService.instance.fetchAndFillMetadata(song);
        count++;
        // Respect MusicBrainz rate limit (1 req/sec)
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {}
    }

    if (mounted) {
      Navigator.pop(context); // Close dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully updated metadata for $count songs.')),
      );
    }
  }

  Future<void> _handleBackup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: BopTheme.green)),
    );

    try {
      final path = await BackupService.instance.createBackup();
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (path != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF282828),
            title: const Text('Backup Created', style: TextStyle(color: Colors.white)),
            content: Text('Your library state has been saved to:\n$path',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: BopTheme.green)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(path)], text: 'Bop Music Player Library Backup');
                },
                child: const Text('Share / Save Elsewhere', style: TextStyle(color: BopTheme.green)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.single.path == null) return;

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Restore Backup?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will merge the backup with your current library. Existing metadata will be overwritten if it exists in the backup.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: BopTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore', style: TextStyle(color: BopTheme.green)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: BopTheme.green)),
    );

    try {
      final counts = await BackupService.instance.restoreBackup(result.files.single.path!);
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text('Restore Complete', style: TextStyle(color: Colors.white)),
          content: Text(
            'Successfully restored:\n• ${counts['songs']} Songs\n• ${counts['playlists']} Playlists\n• ${counts['events']} History Events\n• App Settings applied.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: BopTheme.green)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }

  void _triggerTestNotification(String type) async {
    await NotificationService.instance.showRecapNotification(type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test $type notification triggered!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2E8B57),
              backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
              child: _avatarPath == null ? const Icon(Icons.person, color: Colors.white, size: 18) : null,
            ),
            title: Text(_username),
            subtitle: const Text('Edit Profile'),
            trailing: const Icon(Icons.chevron_right, color: BopTheme.textSecondary),
            onTap: _showEditProfileDialog,
          ),

          // ── Standard settings ─────────────────────
          if (false) // Hidden for now
          ...[
            'Account',
            'Playback',
            'Audio Quality',
            'Storage & Downloads',
            'Local Files',
          ].map((label) => _SettingsTile(label: label)),

          const _SectionDivider(label: 'Bop'),
          const SizedBox(height: 12),
          // ── Bop-specific settings ───────────
          _SettingsTile(
            label: 'Wrapped Cadence',
            trailing: const Text('Monthly',
                style: TextStyle(color: BopTheme.green, fontSize: 13)),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wrapped Cadence is currently locked to Monthly for stability.')),
              );
            },
          ),
          if (false) // Hidden for now
          _SettingsTile(
            label: 'Cloud Sync',
            trailing: const Text('On',
                style: TextStyle(color: BopTheme.green, fontSize: 13)),
          ),
          _SettingsTile(
            label: 'AI Personality & Recap (LMM)',
            trailing: Text(_hasApiKey ? 'Ready' : 'Template Mode',
                style: TextStyle(
                    color: _hasApiKey ? BopTheme.green : BopTheme.textSecondary,
                    fontSize: 13)),
            onTap: _showApiKeyDialog,
          ),

          // ── Local AI Model tile ────────────────────────────────────────────
          ValueListenableBuilder<String?>(
            valueListenable: LlmService.instance.modelStatus,
            builder: (context, status, _) {
              final ai = LlmService.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Model file picker tile ──────────────────────────────
                  ValueListenableBuilder<String?>(
                    valueListenable: ai.modelName,
                    builder: (context, name, _) {
                      // Use the live notifier value, fall back to local state
                      final displayName = (name != null && name.isNotEmpty)
                          ? name
                          : _modelFilename;
                      final hasModel = displayName != 'None' && displayName.isNotEmpty;

                      return _SettingsTile(
                        label: 'Local AI Model (.gguf)',
                        // Always show the filename when one is loaded;
                        // show the status message beneath it as secondary info.
                        subtitle: hasModel
                            ? '$displayName${status != null ? '\n$status' : ''}'
                            : (status ?? 'Requires GGUF format (e.g. TinyLlama-1.1B)'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasModel)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: const Color(0xFF282828),
                                      title: const Text('Delete Model File?',
                                          style: TextStyle(color: Colors.white)),
                                      content: const Text(
                                          'This will remove the GGUF file from your storage permanently.',
                                          style: TextStyle(color: Colors.white70)),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel',
                                              style: TextStyle(
                                                  color: BopTheme.textSecondary)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Delete',
                                              style:
                                                  TextStyle(color: Colors.redAccent)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await ai.clearModel();
                                    _checkApiKey();
                                  }
                                },
                              ),
                            if (_isModelLoading)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: BopTheme.green),
                              )
                            else
                              const Icon(Icons.chevron_right,
                                  color: BopTheme.textSecondary),
                          ],
                        ),
                        onTap: _pickModel,
                      );
                    },
                  ),

                  // ── RAM toggle + generation status (only when model is loaded) ──
                  if (_modelFilename != 'None')
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Active-in-RAM toggle
                          ListTile(
                            dense: true,
                            title: const Text('Active in RAM',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            subtitle: Text(
                              ai.isAiEnabled && ai.isModelLoaded
                                  ? 'AI is ready to generate'
                                  : 'Model is on standby — tap to wake',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Switch(
                              value: ai.isAiEnabled && ai.isModelLoaded,
                              activeColor: BopTheme.green,
                              onChanged: (val) async {
                                await ai.setAiEnabled(val);
                                // Sync the reactive provider so home screen updates
                                ref.read(llmModelReadyProvider.notifier).state = ai.isModelLoaded;
                                if (!val) ref.invalidate(aiPlaylistsProvider);
                                setState(() {});
                              },
                            ),
                          ),

                          // Generation progress indicator
                          ValueListenableBuilder<int>(
                            valueListenable: ai.generationProgress,
                            builder: (context, progress, _) {
                              // Show only while actively generating
                              if (progress == 0 || !ai.isModelLoaded) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding:
                                    const EdgeInsets.only(left: 4, bottom: 10),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: BopTheme.green),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Writing… ($progress words so far)',
                                      style: const TextStyle(
                                        color: BopTheme.green,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),

          _SettingsTile(
            label: 'Download Missing Lyrics',
            onTap: () => _showLyricsDownloadDialog(context),
          ),
          _SettingsTile(
            label: 'Fetch All Missing Metadata',
            subtitle: 'Auto-fill artist, album, and genre tags',
            onTap: _fetchAllMissingMetadata,
          ),

          const _SectionDivider(label: 'Library & Backup'),
          _SettingsTile(
            label: 'Backup Library',
            subtitle: 'Export stats, playlists, and metadata to a JSON file',
            onTap: _handleBackup,
          ),
          _SettingsTile(
            label: 'Restore Library Backup',
            subtitle: 'Import data from a previously saved JSON file',
            onTap: _handleRestore,
          ),
          
          const _SectionDivider(label: 'Playback & Feel'),
          Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(settingsProvider);
              return Column(
                children: [
                  SwitchListTile(
                    title: const Text('Gapless Playback', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Pre-buffer next track for seamless transitions', style: TextStyle(fontSize: 11)),
                    value: settings.gaplessPlayback,
                    activeColor: BopTheme.green,
                    onChanged: (val) => ref.read(settingsProvider.notifier).setGaplessPlayback(val),
                  ),
                  if (settings.gaplessPlayback)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Pre-buffer / Crossfade overlap', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text('${settings.gaplessSeconds}s', style: const TextStyle(color: BopTheme.green, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Slider(
                            value: settings.gaplessSeconds.toDouble(),
                            min: 0,
                            max: 10,
                            divisions: 10,
                            activeColor: BopTheme.green,
                            onChanged: (val) => ref.read(settingsProvider.notifier).setGaplessSeconds(val.toInt()),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          
          const _SectionDivider(label: 'Recap Preview (PREVIEW)'),
          SwitchListTile(
            title: const Text('Simulate November (Teaser)', style: TextStyle(fontSize: 14)),
            value: ref.watch(debugDateProvider)?.month == 11,
            activeColor: BopTheme.green,
            onChanged: (val) {
              ref.read(debugDateProvider.notifier).state = val ? DateTime(2026, 11, 15) : null;
            },
          ),
          SwitchListTile(
            title: const Text('Simulate December (Active)', style: TextStyle(fontSize: 14)),
            value: ref.watch(debugDateProvider)?.month == 12,
            activeColor: BopTheme.green,
            onChanged: (val) {
              ref.read(debugDateProvider.notifier).state = val ? DateTime(2026, 12, 10) : null;
            },
          ),

          const _SectionDivider(label: 'Debug Notifications'),
          _SettingsTile(
            label: 'Trigger Weekly Recap Notification',
            onTap: () => _triggerTestNotification('weekly'),
          ),
          _SettingsTile(
            label: 'Trigger Monthly Recap Notification',
            onTap: () => _triggerTestNotification('monthly'),
          ),
          _SettingsTile(
            label: 'Trigger Annual Recap Notification',
            onTap: () => _triggerTestNotification('annual'),
          ),

          _SettingsTile(
            label: 'About',
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Bop',
                applicationVersion: '2.6.3+5',
                applicationIcon: const Icon(Icons.music_note, color: BopTheme.green),
                children: [
                  const Text('Bop v2.6.3 — Polish & Precision.'),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({required this.label, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(color: BopTheme.textMuted, fontSize: 12))
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: BopTheme.textSecondary),
      onTap: onTap ?? () {},
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: BopTheme.textMuted)),
    );
  }
}