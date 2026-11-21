import 'package:flutter/material.dart';

import 'lan_reading_sync.dart';

class LanReadingPage extends StatelessWidget {
  const LanReadingPage({
    super.key,
    required this.sync,
    required this.reduceMotion,
  });

  final LanReadingSync sync;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('局域网续读')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('当前构建未启用局域网续读', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            '在同一 Wi-Fi 下的设备之间接着上次的位置继续阅读，依赖原工程未公开的模块。'
            '本改版补回了接口，因此工程可以编译，但这一功能本身暂不可用。',
            style: TextStyle(fontSize: 13, height: 1.7, color: muted),
          ),
          const SizedBox(height: 12),
          Text(
            '不影响：书架、阅读进度、书签、听书、本地导入、网盘导入、统计与备份恢复。',
            style: TextStyle(fontSize: 13, height: 1.7, color: muted),
          ),
        ],
      ),
    );
  }
}
