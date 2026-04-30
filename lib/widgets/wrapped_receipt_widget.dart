import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/wrapped_report.dart';

class WrappedReceiptWidget extends StatelessWidget {
  final WrappedReport report;
  final String username;

  const WrappedReceiptWidget({
    super.key,
    required this.report,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, y').format(now).toUpperCase();

    List<dynamic> top5 = [];
    try {
      final data = jsonDecode(report.slidesJsonStr);
      top5 = data['topSongs'] ?? [];
    } catch (_) {}

    return Container(
      width: 320,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'BOP',
            style: TextStyle(
              color: Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              fontFamily: 'Courier',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'RECAP #$dateStr',
            style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 10, fontFamily: 'Courier'),
          ),
          Text(
            'CUSTOMER: ${username.toUpperCase()}',
            style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 10, fontFamily: 'Courier'),
          ),
          Text(
            'PERIOD: ${report.periodLabel.toUpperCase()}',
            style: TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 10, fontFamily: 'Courier'),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.black26, thickness: 1),
          const SizedBox(height: 16),
          
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('QTY  ITEM', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
          ),
          const SizedBox(height: 8),

          ...top5.take(6).map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s['playCount'].toString().padLeft(2, '0')}  ',
                  style: const TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'Courier'),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s['title']}'.toUpperCase(),
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${s['artist']}'.toUpperCase(),
                        style: const TextStyle(color: Colors.black, fontSize: 10, fontFamily: 'Courier'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${s['minutes']}m',
                  style: const TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'Courier'),
                ),
              ],
            ),
          )).toList(),

          const SizedBox(height: 16),
          const Divider(color: Colors.black26, thickness: 1),
          const SizedBox(height: 16),

          _receiptRow('TOTAL MINUTES', report.totalMinutes.toString()),
          _receiptRow('TOTAL SONGS', report.totalSongs.toString()),
          _receiptRow('TOP ARTIST', report.topArtist.toUpperCase()),
          _receiptRow('PERSONALITY', report.personalityType.toUpperCase()),
          
          const SizedBox(height: 24),
          const Text(
            'THANK YOU FOR LISTENING!',
            style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          ),
          const SizedBox(height: 12),
          // Barcode Placeholder
          Container(
            height: 40,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(20, (i) => Container(width: i % 3 == 0 ? 4 : 1, color: Colors.black)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('beatspill.bop', style: TextStyle(color: Colors.black54, fontSize: 8, fontFamily: 'Courier')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
          Text(value, style: const TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'Courier')),
        ],
      ),
    );
  }
}
