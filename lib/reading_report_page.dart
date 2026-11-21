import 'package:flutter/material.dart';

/// 阅读报告页（公开快照缺失，此为实现的最小可用版本）。
class ReadingReportPage extends StatelessWidget {
  const ReadingReportPage({
    super.key,
    this.state,
    this.repository,
    this.now,
    this.initialRange,
  });

  final Object? state;
  final Object? repository;
  final Object? now;
  final Object? initialRange;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('阅读报告')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('阅读报告', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            '原工程的报告页面属于未公开模块，这里提供简化版本：'
            '详细图表与导出请使用「统计」页。',
            style: TextStyle(fontSize: 13, height: 1.7, color: muted),
          ),
        ],
      ),
    );
  }
}
