import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_ui.dart';
import 'wenku8_client.dart';

/// 文库官网网页登录。登录成功后直接读取 WebView 的 Cookie 并返回，
/// 用户不需要手动复制，也不会在每次打开目录时重新登录。
class WenkuWebLoginPage extends StatefulWidget {
  const WenkuWebLoginPage({super.key});

  @override
  State<WenkuWebLoginPage> createState() => _WenkuWebLoginPageState();
}

class _WenkuWebLoginPageState extends State<WenkuWebLoginPage> {
  InAppWebViewController? _web;
  bool _capturing = false;
  String? _error;

  bool _isLoginPage(Uri? uri) {
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path.contains('login') || uri.query.toLowerCase().contains('login');
  }

  Future<void> _capture({bool automatic = false}) async {
    if (_capturing) return;
    final web = _web;
    if (web == null) return;
    final current = await web.getUrl();
    if (automatic && _isLoginPage(current)) return;
    if (!mounted) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final probe = current ?? WebUri(Wenku8Client.webLoginPageUrl);
      final cookies = await CookieManager.instance().getCookies(url: probe);
      final loggedIn = cookies.any(
        (cookie) =>
            cookie.name.toLowerCase() == 'jieqiuserinfo' &&
            cookie.value.trim().isNotEmpty,
      );
      if (!loggedIn) {
        if (mounted && !automatic) {
          setState(() => _error = '还没有检测到文库登录成功。请确认账号已登录并跳到文库页面，再点“完成”。');
        }
        return;
      }
      final header = cookies
          .where((cookie) => cookie.value.isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      if (header.isEmpty) return;
      if (mounted) Navigator.pop(context, header);
    } catch (failure) {
      if (mounted) setState(() => _error = '读取登录 Cookie 失败：$failure');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _considerAutoCapture(Uri? uri) async {
    if (_capturing || _isLoginPage(uri)) return;
    final web = _web;
    if (web == null) return;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: uri == null
            ? WebUri(Wenku8Client.webLoginPageUrl)
            : WebUri(uri.toString()),
      );
      final loggedIn = cookies.any(
        (cookie) =>
            cookie.name.toLowerCase() == 'jieqiuserinfo' &&
            cookie.value.trim().isNotEmpty,
      );
      if (!loggedIn) return;
      // 给站点一点时间把登录后的 Set-Cookie 写进 WebView。
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _capture(automatic: true);
    } catch (_) {
      /* 自动读取失败时不覆盖手动“完成”入口。 */
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('网页登录文库'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _capturing ? null : _capture,
        child: Text(_capturing ? '读取中' : '完成'),
      ),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: AppText(
              '在下面完成官网登录。登录成功跳到文库页面后会自动读取 Cookie；'
              '如果页面没有自动跳转，点右上角“完成”。',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: AppText(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
              ),
            ),
          Expanded(
            child: InAppWebView(
              onWebViewCreated: (controller) => _web = controller,
              initialUrlRequest: URLRequest(
                url: WebUri(Wenku8Client.webLoginPageUrl),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                sharedCookiesEnabled: true,
                thirdPartyCookiesEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              onLoadStop: (_, uri) => unawaited(_considerAutoCapture(uri)),
              onUpdateVisitedHistory: (_, uri, _) =>
                  unawaited(_considerAutoCapture(uri)),
            ),
          ),
        ],
      ),
    ),
  );
}
