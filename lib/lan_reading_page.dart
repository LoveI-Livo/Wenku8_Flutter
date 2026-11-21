import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'feature_pages.dart';
import 'lan_reading_sync.dart';
import 'mod_edition.dart';

/// 「设置 → 局域网续读」。
///
/// 公开源码快照缺少局域网发现与传输模块，本改版按原调用点补回了接口，
/// 这一页负责说明当前状态，避免入口点开就报错。
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
    return ArchiveFeaturePage(
      title: '局域网续读',
      code: 'SYNC / NEARBY',
      child: ListView(
        key: const PageStorageKey('lan-reading'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        children: [
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    ArchiveIcon(CupertinoIcons.wifi_slash, size: 21),
                    SizedBox(width: 12),
                    Expanded(
                      child: AppText(
                        '当前构建未启用局域网续读',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppText(
                  '局域网续读（在同一 Wi-Fi 下的设备之间接着上次的位置继续阅读）'
                  '依赖原工程未公开的模块。本改版补回了调用接口，因此工程可以完整编译，'
                  '但这一功能本身暂不可用。',
                  style: TextStyle(fontSize: 13, height: 1.7, color: muted),
                ),
                const SizedBox(height: 12),
                AppText(
                  '不影响的功能：书架、阅读进度、书签与笔记、听书、本地导入、网盘导入、'
                  '统计与备份恢复。',
                  style: TextStyle(fontSize: 13, height: 1.7, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppText(
            lanSyncDisabledNotice,
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 6),
          AppText(
            '改版 $modEditionVersion · $modAuthorName',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}
