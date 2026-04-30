# Bop v2

An offline-first, premium music player for Android with on-device Bop recaps, intelligent AI curation, and robust backup architecture.

## Version 2.6.2 (Production Release)

### New in v2.6.2
- **Instant App Boot**: Asynchronous LLM background loading completely eliminates startup hang.
- **Advanced Gapless Crossfade**: Live track duration monitoring auto-crossfades music to eliminate baked-in silences at the end of audio files.
- **Robust Backup & Restore**: Full JSON-based library portability. Move your MP3s to a new phone and instantly restore custom lyrics, full play history, and personalized Wrapped Recaps.
- **UI Density & Glassmorphism**: Premium "80/20" frosted-glass bottom navigation and professionally spaced home/stats grids.

## Features

### Local Music Player
- Scans and plays audio files stored on your device
- Advanced Gapless Playback with customizable early-skip crossfades
- Queue management with shuffle, repeat, and sleep timer
- Persistent mini player across all tabs
- Album art automatically extracted and cached

### Listening Stats & Backup
- **Minutes listened**, **unique songs**, **listening streak**, and **skip rate**
- **Heatmap** showing when you listen (AM / PM / Night × Day of week)
- **Top artists** and **Genre breakdowns**
- **Portable Library Backup**: Export and import your entire listening history, lyrics, and metadata to a portable `.json` file that survives across devices.

### Synced Lyrics
- Fetches synced lyrics from lrclib.net automatically
- Lyrics scroll in real-time with playback, centered on the active line
- Tap any lyric line to instantly seek to that timestamp

### Wrapped Recaps (Bop Recap)
- **"Bold Rendition" Design**: A premium 8-card swipeable slideshow featuring dynamic organic/geometric hybrids and floating card aesthetics.
- **Dual-Engine AI**: 
    - **Local GGUF (Mobile AI)**: Full support for on-device LLMs via `llama_cpp_dart`.
- **Shareable Stories**: High-contrast summary cards ready for social sharing.

### AI-Powered Discovery & Curation
- **Intelligent Fallbacks**: Smart Playlists dynamically drop back to algorithm-only mode if AI generation fails or is disabled.
- **Selective Curation**: AI playlists feature dynamic song counts (10–35 tracks), mimicking a human curator's selective ear.

### Library Management
- **All Songs** listing with search, sort by artist/album
- **Multi-Select Bulk Editing**: Long-press to select multiple songs for bulk metadata updates or removal.
- **Smart Metadata Editor**: Manual overrides and Smart Auto-Fill for effortless library cleanup.
- **Rescan** button to pick up newly added files

### Tech Stack
Flutter 3 · Riverpod 2 · Isar 3 · llama_cpp_dart · just_audio · lrclib.net
