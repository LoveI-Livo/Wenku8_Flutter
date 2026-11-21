import 'package:flutter/material.dart';

import 'catalog.dart';
import 'lan_reading_sync.dart';

class LanHandoffMonitor extends StatelessWidget {
  const LanHandoffMonitor({
    super.key,
    required this.handoff,
    required this.onContinue,
    required this.reduceMotion,
    required this.noticeWrapper,
    required this.child,
  });

  final LanHandoffService? handoff;
  final Future<void> Function(LanHandoffReceipt receipt) onContinue;
  final bool reduceMotion;
  final Widget Function(Widget child) noticeWrapper;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class LanSendBookSheet extends StatelessWidget {
  const LanSendBookSheet({
    super.key,
    required this.sync,
    required this.book,
    required this.position,
    required this.reduceMotion,
  });

  final LanReadingSync sync;
  final Novel book;
  final Object? position;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('发送到我的设备', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text('《${book.title}》', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '当前构建未启用局域网续读，无法把阅读位置发送到其它设备。',
            style: TextStyle(fontSize: 13, height: 1.6, color: muted),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }
}
