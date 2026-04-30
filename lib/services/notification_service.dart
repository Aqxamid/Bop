// services/notification_service.dart
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:isar/isar.dart';
import '../services/db_service.dart';
import '../models/song.dart';
import '../models/play_event.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);
    
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap if needed
      },
    );
  }

  /// Schedules notifications for Weekly, Monthly, and Yearly recaps.
  Future<void> scheduleAllRecapReminders() async {
    await scheduleWeeklyRecapReminder();
    await scheduleMonthlyRecapReminder();
    await scheduleYearlyRecapReminder();
  }

  Future<void> scheduleWeeklyRecapReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    // Next Sunday at 7 PM
    int daysUntilSunday = DateTime.sunday - now.weekday;
    if (daysUntilSunday <= 0) daysUntilSunday += 7;

    final scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + daysUntilSunday,
      19, // 7 PM
    );

    final content = await _getWeeklyRecapContent();

    await _scheduleRecap(
      id: 777,
      title: content.title,
      body: content.body,
      date: scheduledDate,
      components: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<({String title, String body})> _getWeeklyRecapContent() async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    
    String topSongText = "tracks";
    try {
      final events = await DbService.instance.isar.playEvents
          .filter()
          .startedAtGreaterThan(weekAgo)
          .findAll();

      if (events.isNotEmpty) {
        final Map<String, int> counts = {};
        for (final e in events) {
          final key = "${e.songTitle} by ${e.artist}";
          counts[key] = (counts[key] ?? 0) + 1;
        }
        final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        topSongText = sorted.first.key;
      }
    } catch (_) {}

    final quotes = [
      "Bop it, don't stop it. Your music misses you!",
      "Ready for another round of ear candy? Bop is waiting.",
      "A new week means new beats. Let's get Bopping!",
      "Your soundtrack is incomplete without today's sessions.",
      "Feeling musical? Your favorite tracks are just a tap away.",
      "The rhythm is calling. Answer it on Bop.",
      "Rediscover your vibe. Your top tracks are ready.",
      "Music is the soul's language. Speak Bop today.",
      "Don't let the silence win. Turn up the Bop.",
      "Your library is gathering digital dust! Let's play some music.",
      "Beat the blues with some Bop. Jump back in!",
      "Your ears deserve the best. They deserve Bop.",
    ];
    final quote = quotes[Random().nextInt(quotes.length)];

    return (
      title: 'Weekly Wrap-up 📈',
      body: 'Your #1 song: $topSongText. $quote',
    );
  }

  Future<void> scheduleMonthlyRecapReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    
    final scheduledDate = tz.TZDateTime(tz.local, lastDay.year, lastDay.month, lastDay.day, 20);

    await _scheduleRecap(
      id: 999,
      title: 'Your Bop Recap is Ready! 🎵',
      body: "Take a look at your listening habits from this month.",
      date: scheduledDate,
      components: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  Future<void> scheduleYearlyRecapReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = tz.TZDateTime(tz.local, now.year, 12, 28, 18); // Dec 28 at 6 PM

    if (now.isAfter(scheduledDate)) return; // Already passed for this year

    await _scheduleRecap(
      id: 1111,
      title: 'Yearly Bop Recap! 🎆',
      body: 'Your 2026 musical journey is ready to be shared.',
      date: scheduledDate,
      components: DateTimeComponents.dateAndTime,
    );
  }

  Future<void> _scheduleRecap({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime date,
    required DateTimeComponents components,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'recap_reminders',
      'Recap Reminders',
      channelDescription: 'Notifications to remind you when your Bop Recap is ready.',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      date,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: components,
    );
  }

  /// Shows a notification immediately for testing purposes.
  Future<void> showRecapNotification(String type) async {
    String title = "Recap Ready!";
    String body = "Check out your stats!";

    if (type == 'weekly') {
      final content = await _getWeeklyRecapContent();
      title = content.title;
      body = content.body;
    } else if (type == 'monthly') {
      title = 'Your Bop Recap is Ready! 🎵';
      body = "Take a look at your listening habits from this month.";
    } else if (type == 'annual') {
      title = 'Yearly Bop Recap! 🎆';
      body = 'Your 2026 musical journey is ready to be shared.';
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'recap_reminders',
      'Recap Reminders',
      channelDescription: 'Notifications to remind you when your Bop Recap is ready.',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _plugin.show(
      type.hashCode, 
      title, 
      body, 
      details
    );
  }

  Future<void> showTestNotification() async {
    await showRecapNotification('weekly');
  }
}
