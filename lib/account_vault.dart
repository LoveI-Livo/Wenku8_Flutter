import 'dart:convert';

import 'package:flutter/services.dart';

/// 文库账号凭据的本机保险箱。
///
/// Android 使用 AndroidKeyStore 加密，iOS 使用 Keychain；两边都保留一份
/// 应用私有目录内的备用密文，覆盖安装/系统升级后仍能自动登录。明文永远
/// 不写 SharedPreferences，也不随普通书架备份上传。
class WenkuAccountCredentials {
  const WenkuAccountCredentials(this.username, this.password);

  final String username, password;

  bool get valid => username.trim().isNotEmpty && password.isNotEmpty;
}

abstract final class WenkuAccountVault {
  static const _channel = MethodChannel('org.mewx.wenku8/cloud_sources');

  static Future<WenkuAccountCredentials?> read() async {
    try {
      final raw = await _channel.invokeMethod<String>('readCredentials');
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final username = decoded['username']?.toString() ?? '';
      final password = decoded['password']?.toString() ?? '';
      final value = WenkuAccountCredentials(username, password);
      return value.valid ? value : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(WenkuAccountCredentials credentials) async {
    if (!credentials.valid) return;
    final raw = jsonEncode({
      'username': credentials.username.trim(),
      'password': credentials.password,
    });
    try {
      await _channel.invokeMethod<void>('writeCredentials', raw);
    } on MissingPluginException {
      // 测试或无宿主环境：不把明文凭据写入普通偏好。
    }
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearCredentials');
    } on MissingPluginException {
      // 同上。
    }
  }
}
