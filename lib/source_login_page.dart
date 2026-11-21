import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_ui.dart';

/// 私有书源网页登录：加载站点登录页，登录完成后自动读取 Cookie。
class SourceLoginPage extends StatefulWidget {
  const SourceLoginPage({super.key, required this.address, this.title = '登录书源'});
  final String address;
  final String title;
  @override
  State<SourceLoginPage> createState() => _SourceLoginPageState();
}

class _SourceLoginPageState extends State<SourceLoginPage> {
  bool _busy = false;
  String? _error;

  Future<void> _capture() async {
    setState(() { _busy = true; _error = null; });
    try {
      final uri = Uri.parse(widget.address);
      final cookies = await CookieManager.instance().getCookies(url: WebUri(widget.address));
      final value = cookies
          .where((c) => c.value.isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (value.isEmpty) {
        setState(() => _error = '还没有读到登录 Cookie，请先在网页里完成登录');
        return;
      }
      if (mounted) Navigator.pop(context, value);
    } catch (e) {
      if (mounted) setState(() => _error = '读取 Cookie 失败：$e');
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
        onPressed: _busy ? null : _capture,
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
                style: TextStyle(color: CupertinoColors.systemRed.resolveFrom(context)),
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
