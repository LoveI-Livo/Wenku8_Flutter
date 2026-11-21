import 'package:flutter/material.dart';

import 'controller.dart';
import 'custom_tts.dart';
import 'models.dart';

/// Settings page for the optional, user supplied Microsoft SSML compatible
/// speech endpoint. Saving switches the listening session to the configured
/// custom voice; cancelling leaves the stored endpoint untouched.
class CustomSpeechPage extends StatefulWidget {
  const CustomSpeechPage({
    super.key,
    required this.settings,
    required this.controller,
  });

  final CustomSpeechSettings settings;
  final ListeningController controller;

  @override
  State<CustomSpeechPage> createState() => _CustomSpeechPageState();
}

class _CustomSpeechPageState extends State<CustomSpeechPage> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _voiceId = TextEditingController();
  final _locale = TextEditingController();
  final _label = TextEditingController();
  final _authHeader = TextEditingController();
  double _rate = 0;
  bool _busy = false;
  bool _failed = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _voiceId.dispose();
    _locale.dispose();
    _label.dispose();
    _authHeader.dispose();
    super.dispose();
  }

  void _fill() {
    final settings = widget.settings;
    _url.text = settings.url;
    _key.text = settings.key;
    _voiceId.text = settings.voiceId;
    _locale.text = settings.locale;
    _label.text = settings.label;
    _authHeader.text = settings.authHeader;
    _rate = settings.rate.toDouble();
  }

  void _show(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _failed = failed;
    });
  }

  void _edited(String _) {
    if (_status == null) return;
    setState(() {
      _status = null;
      _failed = false;
    });
  }

  CustomSpeechConfig? _candidate() => CustomSpeechConfig.tryCreate(
    url: _url.text,
    key: _key.text,
    voiceId: _voiceId.text,
    locale: _locale.text,
    label: _label.text,
    rate: _rate.round(),
    authHeader: _authHeader.text,
    outputFormat: widget.settings.outputFormat,
  );

  Future<void> _save() async {
    final config = _candidate();
    if (config == null) {
      _show('请填写有效的接口地址、密钥、音色与语言', failed: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _failed = false;
    });
    try {
      await widget.settings.apply(config);
      await widget.controller.setVoice(config.voice);
      if (!mounted) return;
      setState(() {
        _status = '已保存并启用 ${config.displayLabel}';
        _failed = false;
      });
    } on SpeechFailure catch (error) {
      _show(error.message, failed: true);
    } catch (_) {
      _show('自定义语音设置暂未保存，请重试', failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final config = _candidate();
    if (config == null) {
      _show('请先填写完整的接口地址、密钥与音色', failed: true);
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在测试接口…';
      _failed = false;
    });
    try {
      final audio = await CustomSpeechClient().synthesize(
        '这是一段自定义语音接口的测试语音。',
        config,
        SpeechCancellation(),
      );
      if (!mounted) return;
      final size = (audio.length / 1024).toStringAsFixed(0);
      setState(() {
        _status = '接口可用，已生成 $size KB 语音';
        _failed = false;
      });
    } on SpeechFailure catch (error) {
      _show(error.message, failed: true);
    } catch (_) {
      _show('接口暂不可用，请检查配置', failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _status = null;
      _failed = false;
    });
    try {
      await widget.settings.reset();
      if (!mounted) return;
      setState(() {
        _fill();
        _status = '已清除自定义语音接口配置';
        _failed = false;
      });
    } catch (_) {
      _show('清除设置失败，请重试', failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final config = widget.settings.config;
    return Scaffold(
      appBar: AppBar(title: const Text('自定义语音接口')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              '按照 Microsoft 语音合成 SSML 协议请求你自己的接口。'
              '未配置或配置不完整时，听书仍使用内置音源。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('custom-speech-url'),
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: _edited,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://example.com/cognitiveservices/v1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('custom-speech-key'),
              controller: _key,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              onChanged: _edited,
              decoration: const InputDecoration(
                labelText: '订阅密钥 / 访问令牌',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('custom-speech-auth-header'),
              controller: _authHeader,
              enabled: !_busy,
              autocorrect: false,
              onChanged: _edited,
              decoration: const InputDecoration(
                labelText: '鉴权请求头',
                hintText: defaultCustomSpeechAuthHeader,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              '音色与语速',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('custom-speech-voice'),
              controller: _voiceId,
              enabled: !_busy,
              autocorrect: false,
              onChanged: _edited,
              decoration: const InputDecoration(
                labelText: '音色名称',
                hintText: 'zh-CN-XiaoxiaoNeural',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom-speech-locale'),
                    controller: _locale,
                    enabled: !_busy,
                    autocorrect: false,
                    onChanged: _edited,
                    decoration: const InputDecoration(
                      labelText: '语言',
                      hintText: 'zh-CN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom-speech-label'),
                    controller: _label,
                    enabled: !_busy,
                    onChanged: _edited,
                    decoration: const InputDecoration(
                      labelText: '显示名称（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('语速'),
                Expanded(
                  child: Slider(
                    key: const ValueKey('custom-speech-rate'),
                    value: _rate
                        .clamp(
                          customSpeechMinimumRatePercent.toDouble(),
                          customSpeechMaximumRatePercent.toDouble(),
                        )
                        .toDouble(),
                    min: customSpeechMinimumRatePercent.toDouble(),
                    max: customSpeechMaximumRatePercent.toDouble(),
                    divisions: 30,
                    label: '${_rate.round()}%',
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _rate = value),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${_rate.round()}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('custom-speech-save'),
                    onPressed: _busy ? null : _save,
                    child: const Text('保存并启用'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('custom-speech-test'),
                    onPressed: _busy ? null : _test,
                    child: const Text('测试接口'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('custom-speech-reset'),
                onPressed: _busy ? null : _reset,
                child: const Text('清除配置'),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                key: const ValueKey('custom-speech-status'),
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: _failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              config == null
                  ? '当前尚未配置自定义语音接口'
                  : '当前音色：${config.displayLabel} · ${config.locale} · ${config.rateLabel}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
