import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'cloud_guangya.dart';
import 'cloud_sources.dart';

/// 光鸭云盘没有公开的网页 token 读取位置，直接在 App 内走官网短信登录，
/// 不要求用户安装光鸭 App，也不把手机号或验证码写进任何备份。
class GuangyaLoginPage extends StatefulWidget {
  const GuangyaLoginPage({super.key});
  @override
  State<GuangyaLoginPage> createState() => _GuangyaLoginPageState();
}

class _GuangyaLoginPageState extends State<GuangyaLoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _auth = GuangyaAuth();
  String? _verificationId, _captcha, _device;
  String? _error;
  bool _sending = false, _loggingIn = false, _sent = false;

  @override
  void dispose() {
    _auth.http.close();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = GuangyaAuth.normalizePhone(_phone.text);
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位手机号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await _auth.requestCode(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _verificationId = result.verificationId;
        _captcha = result.captcha;
        _device = result.device;
      });
      showNovelFeedback(context, '验证码已发送，请查看手机短信');
    } catch (error) {
      if (mounted) setState(() => _error = cloudFailureMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    final phone = GuangyaAuth.normalizePhone(_phone.text);
    final code = _code.text.trim();
    final verificationId = _verificationId;
    if (!_sent ||
        verificationId == null ||
        _captcha == null ||
        _device == null) {
      setState(() => _error = '请先获取短信验证码');
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      setState(() => _error = '请输入短信中的验证码');
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      final session = await _auth.verifyCode(
        phone: phone,
        code: code,
        verificationId: verificationId,
        captcha: _captcha!,
        device: _device!,
      );
      if (mounted) Navigator.pop(context, session);
    } catch (error) {
      if (mounted) setState(() => _error = cloudFailureMessage(error));
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    ),
    navigationBar: const CupertinoNavigationBar(middle: Text('登录光鸭云盘')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          const ArchiveSection(title: '光鸭云盘', code: 'GUANGYA / ACCOUNT LOGIN'),
          const SizedBox(height: 8),
          const AppText(
            '使用光鸭云盘绑定的手机号登录。验证码只用于本次登录，不会保存到书架或备份。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 18),
          _field(
            key: const ValueKey('guangya-phone'),
            controller: _phone,
            placeholder: '手机号',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(
                  key: const ValueKey('guangya-code'),
                  controller: _code,
                  placeholder: _sent ? '输入短信验证码' : '先获取验证码',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              CupertinoButton(
                key: const ValueKey('guangya-send-code'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                color: CupertinoColors.systemGrey5.resolveFrom(context),
                onPressed: _sending || _loggingIn ? null : _sendCode,
                child: AppText(
                  _sending ? '发送中' : (_sent ? '重新发送' : '获取验证码'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AppText(
              _error!,
              style: TextStyle(
                color: CupertinoColors.systemRed.resolveFrom(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 22),
          GlassPillButton(
            key: const ValueKey('guangya-login'),
            icon: CupertinoIcons.person_badge_plus,
            label: _loggingIn ? '正在登录…' : '登录并保存',
            loading: _loggingIn,
            onPressed: _loggingIn ? null : _login,
          ),
          const SizedBox(height: 16),
          const AppText(
            '登录成功后即可浏览光鸭云盘全部文件，书籍在线阅读，不下载原文件。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: CupertinoColors.tertiaryLabel,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String placeholder,
    required TextInputType keyboardType,
  }) => CupertinoTextField(
    key: key,
    controller: controller,
    placeholder: placeholder,
    keyboardType: keyboardType,
    textInputAction: TextInputAction.next,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: CupertinoColors.separator.resolveFrom(context),
        width: 0.5,
      ),
    ),
  );
}
