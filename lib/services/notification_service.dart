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
      "Your ears called. They demand their weekly soundtrack.",
      "Time to face the music. Literally. Your weekly stats are in.",
      "We judged your music taste so you don't have to.",
      "Another week of pretending your playlist isn't entirely chaotic.",
      "Spoiler alert: You listened to that one song way too much.",
      "Let's see if you finally diversified your listening habits. (Probably not).",
      "Your weekly audio footprint is ready for inspection.",
      "Data doesn't lie, but your 'Guilty Pleasures' playlist sure does.",
      "Ready to see exactly how much time you spent avoiding reality?",
    ];
    final quote = quotes[Random().nextInt(quotes.length)];

    final titles = [
      "Your Weekly Autopsy",
      "The Damage is Done",
      "Weekly Audio Receipts",
      "Music Math: Weekly Edition",
      "Your Weekly Soundtrack",
    ];
    final title = titles[Random().nextInt(titles.length)];

    return (
      title: title,
      body: 'Top track: $topSongText. $quote',
    );
  }

  Future<void> scheduleMonthlyRecapReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    
    final scheduledDate = tz.TZDateTime(tz.local, lastDay.year, lastDay.month, lastDay.day, 20);

    final titles = [
      "Monthly Reality Check",
      "The End of Month Vibe Check",
      "Thirty Days of Audio History",
      "Monthly Music Receipts",
      "Your Sonic Footprint"
    ];
    
    final bodies = [
      "Time to see exactly what you used to block out the world this month.",
      "Your monthly stats are calculated. Brace yourself.",
      "Let's review the soundtrack of your last 30 days.",
      "The data is in. Yes, you really listened to that song that much.",
      "Your monthly listening habits, exposed for your viewing pleasure.",
    ];
    
    final title = titles[Random().nextInt(titles.length)];
    final body = bodies[Random().nextInt(bodies.length)];

    await _scheduleRecap(
      id: 999,
      title: title,
      body: body,
      date: scheduledDate,
      components: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  Future<void> scheduleYearlyRecapReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = tz.TZDateTime(tz.local, now.year, 12, 28, 18); // Dec 28 at 6 PM

    if (now.isAfter(scheduledDate)) return; // Already passed for this year

    final titles = [
      "The Final Boss of Recaps",
      "Your Year in Audio",
      "The Ultimate Vibe Check",
      "365 Days of Escapism",
      "Your Yearly Sonic Receipts"
    ];
    
    final bodies = [
      "A whole year of questionable music choices, summarized nicely.",
      "It's time. Your definitive annual listening data has arrived.",
      "Ready to see what got you through the year?",
      "The annual judgment day for your music taste is here.",
    ];
    
    final title = titles[Random().nextInt(titles.length)];
    final body = bodies[Random().nextInt(bodies.length)];

    await _scheduleRecap(
      id: 1111,
      title: title,
      body: body,
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
      'recap_reminders_v2',
      'Recap Reminders',
      channelDescription: 'Notifications to remind you when your Bop Recap is ready.',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('bop_notification'),
      playSound: true,
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
      title = 'Monthly Reality Check';
      body = "Take a look at your listening habits from this month.";
    } else if (type == 'annual') {
      title = 'Your Year in Audio';
      body = 'Your musical journey is ready to be shared.';
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'recap_reminders_v2',
      'Recap Reminders',
      channelDescription: 'Notifications to remind you when your Bop Recap is ready.',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('bop_notification'),
      playSound: true,
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
