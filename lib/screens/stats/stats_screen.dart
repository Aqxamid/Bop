// screens/stats/stats_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/stats_provider.dart';
import '../../services/wrapped_generator.dart';
import '../../services/llm_service.dart';
import '../wrapped/wrapped_slideshow_screen.dart';
import '../../widgets/mini_player.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final minutes = ref.watch(minutesProvider);
    final songs = ref.watch(songCountProvider);
    final streak = ref.watch(streakProvider);
    final skipRate = ref.watch(skipRateProvider);
    final topArtists = ref.watch(topArtistsProvider);
    final heatmap = ref.watch(heatmapProvider);
    final genres = ref.watch(genreBreakdownProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 120),
      children: [

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your Stats',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  _PeriodToggle(
                    current: ref.watch(statsPeriodProvider),
                    onChanged: (p) => ref.read(statsPeriodProvider.notifier).state = p,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RecapTriggerCard(
                generating: _generating,
                onTap: _generateRecap,
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  _StatCard(
                    label: 'Minutes',
                    value: minutes.when(
                      data: (v) => _fmt(v),
                      loading: () => '…',
                      error: (_, __) => '—',
                    ),
                    icon: Icons.headphones,
                    color: BopTheme.purple,
                  ),
                  _StatCard(
                    label: 'Songs',
                    value: songs.when(
                      data: (v) => _fmt(v),
                      loading: () => '…',
                      error: (_, __) => '—',
                    ),
                    icon: Icons.music_note,
                    color: BopTheme.green,
                  ),
                  _StatCard(
                    label: 'Streak',
                    value: streak.when(
                      data: (v) => '${v}d',
                      loading: () => '…',
                      error: (_, __) => '—',
                    ),
                    icon: Icons.local_fire_department,
                    color: BopTheme.orange,
                  ),
                  _StatCard(
                    label: 'Skip Rate',
                    value: skipRate.when(
                      data: (v) => '${(v * 100).round()}%',
                      loading: () => '…',
                      error: (_, __) => '—',
                    ),
                    icon: Icons.skip_next,
                    color: BopTheme.red,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Top artists this month',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              topArtists.when(
                data: (artists) {
                  if (artists.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Play some songs to see your top artists',
                          style: TextStyle(color: BopTheme.textMuted)),
                    );
                  }
                  final maxVal = artists.first.value;
                  return Column(
                    children: artists
                        .map((a) => _BarRow(
                              label: a.key,
                              value: a.value,
                              max: maxVal,
                            ))
                        .toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('Error loading data'),
              ),
              const SizedBox(height: 2),
              Text('When you listen',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              heatmap.when(
                data: (matrix) {
                  final condensed = _condenseHeatmap(matrix);
                  return _HeatmapWidget(matrix: condensed);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('Error loading data'),
              ),
              const SizedBox(height: 8),
              Text('Genre breakdown',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 0),
              genres.when(
                data: (genreMap) {
                  if (genreMap.isEmpty) return const Text('No genre data yet');
                  final total = genreMap.values.fold<int>(0, (sum, v) => sum + v);
                  final sorted = genreMap.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  final colors = [
                    BopTheme.green,
                    BopTheme.purple,
                    BopTheme.red,
                    BopTheme.orange,
                    BopTheme.blue,
                  ];
                  return Column(
                    children: sorted.asMap().entries.map((entry) {
                      final pct = total > 0 ? entry.value.value / total : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _BarRow(
                          label: entry.value.key,
                          value: (pct * 100).round(),
                          max: 100,
                          color: colors[entry.key % colors.length],
                          suffix: '${(pct * 100).round()}%',
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('Error loading data'),
              ),
      ],
    );
  }

  List<List<int>> _condenseHeatmap(List<List<int>> full) {
    final condensed = List.generate(3, (_) => List.filled(7, 0));
    for (int day = 0; day < 7 && day < full.length; day++) {
      for (int h = 0; h < 24 && h < full[day].length; h++) {
        final row = h < 12 ? 0 : (h < 18 ? 1 : 2);
        condensed[row][day] += full[day][h];
      }
    }
    int maxVal = 1;
    for (final row in condensed) {
      for (final v in row) {
        if (v > maxVal) maxVal = v;
      }
    }
    return condensed
        .map((row) => row.map((v) => (v * 3 / maxVal).round().clamp(0, 3)).toList())
        .toList();
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Future<void> _generateRecap({bool yearly = false}) async {
    final minutes = ref.read(minutesProvider).value ?? 0;
    if (minutes < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bop needs at least 1 minute of play history to generate your Recap.')),
      );
      return;
    }
    setState(() => _generating = true);
    final now = ref.read(debugDateProvider) ?? DateTime.now();
    // Use current month for Recap as requested
    final targetMonth = now.month;
    final targetYear = now.year;

    try {
      final report = yearly 
          ? await WrappedGenerator.instance.generateYearly(now.year)
          : await WrappedGenerator.instance.generate(targetYear, targetMonth);

      if (mounted) {
        // Double check recap is there if AI is enabled
        if (report.llmRecap.isEmpty && LlmService.instance.isAiEnabled) {
          // One final attempt if something went wrong
          final recap = await LlmService.instance.generateWrappedRecap(report);
          report.llmRecap = recap;
        }
        
        Navigator.push(context, MaterialPageRoute(builder: (_) => WrappedSlideshowScreen(report: report)));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

class _RecapTriggerCard extends ConsumerWidget {
  final bool generating;
  final Function({bool yearly}) onTap;
  const _RecapTriggerCard({required this.generating, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(debugDateProvider) ?? DateTime.now();
    final isNovember = now.month == 11;
    final isDecember = now.month == 12;
    final isYearlyTime = isDecember && now.day <= 21;

    if (isNovember) {
      return Column(
        children: [
          _buildMonthlyCard(context, now, generating, onTap),
          const SizedBox(height: 12),
          _buildTeaser(context),
        ],
      );
    }
    if (isYearlyTime) {
      return Column(
        children: [
          _buildMonthlyCard(context, now, generating, onTap),
          const SizedBox(height: 12),
          _buildYearlyCard(context, now, generating, onTap),
        ],
      );
    }
    return _buildMonthlyCard(context, now, generating, onTap);
  }

  Widget _buildTeaser(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: BopTheme.green, size: 32),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Coming Soon: Bop Recap', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Your annual recap is coming in December.', style: TextStyle(color: BopTheme.textMuted, fontSize: 12)),
          ])),
        ],
      ),
    );
  }

  Widget _buildMonthlyCard(BuildContext context, DateTime now, bool generating, Function({bool yearly}) onTap) {
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return _BaseRecapCard(
      title: '${months[now.month]} Recap',
      subtitle: 'Your musical journey in ${months[now.month]}',
      generating: generating,
      onTap: () => onTap(yearly: false),
      gradient: const LinearGradient(colors: [BopTheme.green, Colors.teal]),
    );
  }

  Widget _buildYearlyCard(BuildContext context, DateTime now, bool generating, Function({bool yearly}) onTap) {
    return _BaseRecapCard(
      title: 'Annual Recap ${now.year}',
      subtitle: 'Celebrating your year in music',
      generating: generating,
      onTap: () => onTap(yearly: true),
      isYearly: true,
      gradient: const LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFF8E44AD)]),
    );
  }
}

class _BaseRecapCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool generating;
  final VoidCallback onTap;
  final Gradient gradient;
  final bool isYearly;
  const _BaseRecapCard({required this.title, required this.subtitle, required this.generating, required this.onTap, required this.gradient, this.isYearly = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: (isYearly ? Colors.amber : BopTheme.green).withOpacity(0.2), blurRadius: 16)]),
      child: Stack(children: [
        Positioned(top: -50, right: -30, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [(isYearly ? Colors.amber : BopTheme.green).withOpacity(0.5), Colors.transparent])))),
        Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          InkWell(onTap: generating ? null : onTap, borderRadius: BorderRadius.circular(24), child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(24)), child: generating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('See Recap', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14)))),
        ])),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: BopTheme.surface, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: color, size: 18), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: BopTheme.textMuted, fontSize: 10))])]));
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;
  final String? suffix;
  const _BarRow({required this.label, required this.value, required this.max, this.color = BopTheme.green, this.suffix});
  @override
  Widget build(BuildContext context) {
    return Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)), Text(suffix ?? '$value', style: const TextStyle(color: BopTheme.textSecondary, fontSize: 12))]), const SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: max > 0 ? value / max : 0, backgroundColor: BopTheme.surfaceAlt, valueColor: AlwaysStoppedAnimation(color), minHeight: 5)), const SizedBox(height: 4)]);
  }
}

class _HeatmapWidget extends StatelessWidget {
  final List<List<int>> matrix;
  const _HeatmapWidget({required this.matrix});
  Color _cellColor(int intensity) {
    switch (intensity) {
      case 0: return BopTheme.surfaceAlt;
      case 1: return const Color(0xFF1A3D21);
      case 2: return const Color(0xFF145A32);
      default: return BopTheme.green;
    }
  }
  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const SizedBox(width: 36), ...days.map((d) => Expanded(child: Text(d, style: const TextStyle(color: BopTheme.textMuted, fontSize: 9), textAlign: TextAlign.center)))]), const SizedBox(height: 4), ...matrix.asMap().entries.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [SizedBox(width: 36, child: Text(['AM', 'PM', 'Night'][entry.key], style: const TextStyle(color: BopTheme.textMuted, fontSize: 9))), ...entry.value.map((intensity) => Expanded(child: Container(height: 14, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: _cellColor(intensity), borderRadius: BorderRadius.circular(2)))))])))]);
  }
}

class _PeriodToggle extends StatelessWidget {
  final StatsPeriod current;
  final ValueChanged<StatsPeriod> onChanged;
  const _PeriodToggle({required this.current, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final periods = [(StatsPeriod.week, 'W'), (StatsPeriod.month, 'M'), (StatsPeriod.quarter, 'Q'), (StatsPeriod.allTime, 'All')];
    return Row(children: periods.map((p) {
      final active = p.$1 == current;
      return InkWell(
        onTap: () => onChanged(p.$1),
        borderRadius: BorderRadius.circular(20),
        child: Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: active ? BopTheme.green : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: active ? null : Border.all(color: BopTheme.textMuted)),
            child: Text(p.$2,
                style: TextStyle(
                    color: active ? Colors.black : BopTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11))),
      );
    }).toList());
  }
}
