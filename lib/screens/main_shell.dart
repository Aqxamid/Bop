// screens/main_shell.dart
// Root scaffold with persistent bottom nav: Home | Search | Stats | Library
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../providers/stats_provider.dart';

import '../theme/app_theme.dart';
import 'library/home_screen.dart';
import 'library/search_screen.dart';
import 'stats/stats_screen.dart';
import 'library/library_screen.dart';
import '../widgets/global_ai_status_indicator.dart';
import '../widgets/mini_player.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _screens = [
    HomeScreen(),
    SearchScreen(),
    StatsScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(shellTabIndexProvider);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        // 1. If on Search and a genre is selected, go back to browse categories
        if (currentIndex == 1) {
          final selectedGenre = ref.read(searchGenreProvider);
          if (selectedGenre != null) {
            ref.read(searchGenreProvider.notifier).state = null;
            return;
          }
        }

        // 2. If not on Home, go back to Home
        if (currentIndex != 0) {
          ref.read(shellTabIndexProvider.notifier).state = 0;
          return;
        }

        // 2. If on Home, show exit confirmation
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF282828),
            title: const Text('Exit Bop?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text('Are you sure you want to exit the player?', style: TextStyle(color: BopTheme.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('EXIT', style: TextStyle(color: BopTheme.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          // In Flutter, to exit the app programmatically on Android:
          // SystemNavigator.pop() is generally preferred.
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(
              index: currentIndex,
              children: _screens,
            ),
            const GlobalAiStatusIndicator(),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 76, // Elevated slightly more for better breathing room
              child: MiniPlayer(),
            ),
          ],
        ),
        bottomNavigationBar: _BopNavBar(
          currentIndex: currentIndex,
          onTap: (i) => ref.read(shellTabIndexProvider.notifier).state = i,
        ),
      ),
    );
  }
}

// ── Custom bottom nav ─────────────────────────────────────────
class _BopNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BopNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home, Icons.home_outlined, 'Home'),
      (Icons.search, Icons.search_outlined, 'Search'),
      (Icons.bar_chart, Icons.bar_chart_outlined, 'Stats'),
      (Icons.library_music, Icons.library_music_outlined, 'Library'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFA121212),
        border: const Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final isActive = i == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isActive ? item.$1 : item.$2,
                        color: isActive ? BopTheme.textPrimary : BopTheme.textSecondary,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        style: TextStyle(
                          fontSize: 10,
                          color: isActive ? BopTheme.textPrimary : BopTheme.textSecondary,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
