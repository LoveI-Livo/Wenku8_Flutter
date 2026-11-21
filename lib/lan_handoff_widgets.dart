import 'package:flutter/widgets.dart';

import 'lan_reading_sync.dart';

/// 局域网续读的全局提醒层。
///
/// 收到其他设备的续读请求时，[noticeWrapper] 会包一层阅读器外观并把提醒显示在页面上；
/// 本构建没有请求来源，因此始终直接返回 [child]，不额外占用布局或帧。
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
