import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'lan_reading_sync.dart';

class LanReadingPage extends StatefulWidget {
  const LanReadingPage({
    super.key,
    required this.sync,
    required this.reduceMotion,
  });

  final LanReadingSync sync;
  final bool reduceMotion;

  @override
  State<LanReadingPage> createState() => _LanReadingPageState();
}

class _LanReadingPageState extends State<LanReadingPage> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.sync.prepareIdentity().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (value) {
      final opened = await widget.sync.enable();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!opened) {
        showNovelFeedback(context, '未获得本地网络权限，请到系统设置允许后再开启');
      } else {
        showNovelFeedback(context, '局域网续读已开启');
      }
    } else {
      await widget.sync.disable();
      if (!mounted) return;
      setState(() => _busy = false);
      showNovelFeedback(context, '局域网续读已关闭');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final enabled = sync.listening;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('局域网续读')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Icon(enabled ? Icons.wifi_tethering : Icons.wifi_off, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  enabled ? '局域网续读已开启' : '局域网续读已关闭',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '自动同步阅读记录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      key: const ValueKey('lan-reading-enabled'),
                      value: enabled,
                      onChanged: _busy ? null : _toggle,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '两台设备连上同一 Wi-Fi 或手机热点，首次确认自己的设备，以后自动连接。'
                  '进度、书签与分类自动增量同步，两端 App 需保持前台。',
                  style: TextStyle(fontSize: 13, height: 1.7, color: muted),
                ),
                if (enabled) ...[
                  const SizedBox(height: 10),
                  Text(
                    '本机：${sync.deviceName}',
                    style: TextStyle(fontSize: 13, height: 1.6, color: muted),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    '开启时系统会弹出本地网络权限提示，请选择允许。若没有弹出，'
                    '可到系统设置中允许本 App 访问本地网络。',
                    style: TextStyle(fontSize: 13, height: 1.7, color: muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('要求', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '· 两台设备都已安装本 App，并允许本地网络权限\n'
            '· 两台设备在同一 Wi-Fi，且不是访客网络隔离\n'
            '· 接收方已导入或缓存同一本书\n'
            '· 续读只传章节与阅读位置，不传账号、Cookie、书源密码或整本书',
            style: TextStyle(fontSize: 13, height: 1.8, color: muted),
          ),
          const SizedBox(height: 20),
          Text(
            '如果系统没有弹出本地网络授权，请到系统设置中允许本 App 访问本地网络。',
            style: TextStyle(fontSize: 12, height: 1.7, color: muted),
          ),
        ],
      ),
    );
  }
}
