import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../models/wrapped_report.dart';

class WrappedReceiptWidget extends StatelessWidget {
  final WrappedReport report;
  final String username;
  final Uint8List? bgBytes;

  const WrappedReceiptWidget({
    super.key,
    required this.report,
    required this.username,
    this.bgBytes,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, y').format(now).toUpperCase();

    List<dynamic> topSongs = [];
    try {
      final data = jsonDecode(report.slidesJsonStr);
      topSongs = data['topSongs'] ?? [];
    } catch (_) {}

    return Container(
      width: 340,
      color: const Color(0xFFF3F3F3),
      child: Stack(
        children: [
          Positioned.fill(
            child: bgBytes != null
              ? Image.memory(
                  bgBytes!,
                  repeat: ImageRepeat.repeat,
                  opacity: const AlwaysStoppedAnimation(0.9),
                )
              : Image.asset(
                  'assets/images/receipt_bg.png',
                  repeat: ImageRepeat.repeat,
                  opacity: const AlwaysStoppedAnimation(0.9),
                ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'BOP',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontFamily: 'Courier',
                  ),
                ),
          const SizedBox(height: 8),
          Text(
            report.periodLabel.toUpperCase(),
            style: const TextStyle(color: Colors.black87, fontSize: 14, fontFamily: 'Courier', fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ORDER #0001 FOR ${username.toUpperCase()}', style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(dateStr, style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          _dashedLine(),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('QTY  ITEM', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              Text('AMT', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
            ],
          ),
          const SizedBox(height: 8),
          _dashedLine(),
          const SizedBox(height: 12),
          
          // Songs List (Limited to 9, 10th is N MORE)
          ...List.generate(
            topSongs.length > 10 ? 9 : topSongs.length,
            (index) {
              final song = topSongs[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(index + 1).toString().padLeft(2, '0')}   ',
                      style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        '${song['title']}'.toUpperCase(),
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${song['minutes'] ?? song['playCount'] ?? 0}',
                      style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }
          ),

          if (topSongs.length > 10)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text('10   ', style: TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                  Text(
                    '... AND ${topSongs.length - 9} MORE',
                    style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          _dashedLine(),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ITEM COUNT:', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
              Text('${report.totalSongs}', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL:', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
              Text('${report.totalMinutes}', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
            ],
          ),
          
          const SizedBox(height: 8),
          _dashedLine(),
          const SizedBox(height: 8),
          
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CARD #: **** **** **** ${now.year}', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
                const SizedBox(height: 4),
                const Text('AUTH CODE: 123421', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
                const SizedBox(height: 4),
                Text('CARDHOLDER: ${username.toUpperCase()}', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Courier')),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text(
            'THANK YOU FOR VISITING!',
            style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          ),
          const SizedBox(height: 20),
          
          // Scannable Barcode
          SizedBox(
            height: 60,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: 'Made via Bop - Aquamid',
              drawText: false,
              color: Colors.black,
            ),
          ),
          
          const SizedBox(height: 12),
          const Text('beatspill.bop', style: TextStyle(color: Colors.black87, fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  ],
),
);
  }

  Widget _dashedLine() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 6.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54),
              ),
            );
          }),
        );
      },
    );
  }
}
