import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'catalog.dart';
import 'lan_reading_sync.dart';
import 'library_state.dart';

/// Shows the most recent offer as a floating card without covering the app.
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
  Widget build(BuildContext context) {
    final service = handoff;
    if (service == null) return child;
    return AnimatedBuilder(
      animation: service,
      child: child,
      builder: (context, content) {
        final receipt = service.received;
        if (receipt == null) return content!;
        return Stack(
          children: [
            Positioned.fill(child: content!),
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              child: noticeWrapper(
                Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: .96),
                  elevation: 12,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const ArchiveIcon(CupertinoIcons.wifi, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AppText(
                                '${receipt.deviceName} 正在读',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        AppText(
                          '《${receipt.title.isEmpty ? '未命名书籍' : receipt.title}》 · 第 ${receipt.position.chapter + 1} 章',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: service.dismissReceipt,
                              child: const Text('忽略'),
                            ),
                            const SizedBox(width: 4),
                            FilledButton(
                              onPressed: () => unawaited(onContinue(receipt)),
                              child: const Text('继续阅读'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class LanSendBookSheet extends StatefulWidget {
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
  State<LanSendBookSheet> createState() => _LanSendBookSheetState();
}

class _LanSendBookSheetState extends State<LanSendBookSheet> {
  bool _sending = false;
  String? _result;

  Future<void> _send() async {
    final position = widget.position;
    if (position is! ReadingPosition) {
      setState(() => _result = '阅读位置尚未准备好，请回到正文后再试');
      return;
    }
    setState(() {
      _sending = true;
      _result = null;
    });
    final sent = await widget.sync.send(widget.book, position);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = sent
          ? '已广播续读位置。另一台设备保持同一 Wi-Fi，打开同一本书后可选择继续。'
          : '发送失败：请确认两台设备在同一 Wi-Fi，并允许 App 使用本地网络。';
    });
  }

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
          Text(
            '《${widget.book.title}》',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '两台设备连同一个 Wi-Fi。发送后，另一台设备会收到续读卡片；本机需要已有同一本书。',
            style: TextStyle(fontSize: 13, height: 1.6, color: muted),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Text(
              _result!,
              style: TextStyle(fontSize: 13, height: 1.6, color: muted),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? '正在发送…' : '发送续读位置'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
