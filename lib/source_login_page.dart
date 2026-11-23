import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_ui.dart';

/// 私有书源网页登录：加载站点登录页，登录完成后自动读取 Cookie。
class SourceLoginPage extends StatefulWidget {
  const SourceLoginPage({
    super.key,
    required this.address,
    this.title = '登录书源',
    this.autoCookieNames = const [],
  });
  final String address;
  final String title;

  /// When every named cookie appears, finish automatically. This is how a QR
  /// or SMS login on the provider's own page becomes a usable app session.
  final List<String> autoCookieNames;
  @override
  State<SourceLoginPage> createState() => _SourceLoginPageState();
}

class _SourceLoginPageState extends State<SourceLoginPage> {
  bool _busy = false;
  String? _error;
  Timer? _autoTimer;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoCookieNames.isNotEmpty) {
      _autoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_autoTried) _capture(auto: true);
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _capture({bool auto = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (!auto) _error = null;
    });
    try {
      // 登录页经常在 /login、/mydisk.php 等子路径，只按当前地址读取会漏掉
      // 域名级 Cookie。这里同时读取当前页与站点根路径，合并去重。
      final uri = Uri.tryParse(widget.address);
      final probes = <String>{
        widget.address,
        if (uri != null) Uri(scheme: uri.scheme, host: uri.host).toString(),
      };
      final byName = <String, String>{};
      for (final probe in probes) {
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri(probe),
        );
        for (final cookie in cookies) {
          if (cookie.value.isNotEmpty) byName[cookie.name] = cookie.value;
        }
      }
      final cookies = [
        for (final entry in byName.entries)
          (name: entry.key, value: entry.value),
      ];
      final value = cookies
          .where((c) => c.value.isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (value.isEmpty) {
        if (!auto) setState(() => _error = '还没有读到登录 Cookie，请先在网页里完成登录');
        return;
      }
      if (auto) {
        final names = {for (final c in cookies) c.name};
        if (!widget.autoCookieNames.every(names.contains)) return;
        _autoTried = true;
      }
      if (mounted) Navigator.pop(context, value);
    } catch (e) {
      if (!auto && mounted) setState(() => _error = '读取 Cookie 失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: Text(widget.title),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _busy ? null : () => _capture(),
        child: Text(_busy ? '读取中' : '完成'),
      ),
    ),
    child: SafeArea(
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: AppText(
                _error!,
                style: TextStyle(
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.address)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                sharedCookiesEnabled: true,
                thirdPartyCookiesEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
