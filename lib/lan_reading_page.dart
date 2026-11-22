import 'package:flutter/material.dart';

import 'app_ui.dart';
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
          Row(
            children: [
              Icon(
                sync.listening ? Icons.wifi_tethering : Icons.wifi_off,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sync.listening ? '局域网续读已开启' : '局域网续读未能启动',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '本机：${sync.deviceName}\n'
            '两台设备连同一个 Wi-Fi，不需要登录、不需要服务器。'
            '在阅读器里打开「发送到我的设备」，另一台设备会自动弹出续读卡片。',
            style: TextStyle(fontSize: 13, height: 1.7, color: muted),
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
