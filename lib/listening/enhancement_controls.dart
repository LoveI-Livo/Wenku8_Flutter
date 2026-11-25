import 'package:flutter/material.dart';

import 'enhancement.dart';

/// Compact selector embedded in the listening panel. The owning controller
/// persists every committed value through [onChanged].
class ListeningEnhancementSettings extends StatefulWidget {
  const ListeningEnhancementSettings({
    super.key,
    required this.enhancement,
    required this.onChanged,
  });

  final ListeningEnhancement enhancement;
  final ValueChanged<ListeningEnhancementPreference> onChanged;

  @override
  State<ListeningEnhancementSettings> createState() =>
      _ListeningEnhancementSettingsState();
}

class _ListeningEnhancementSettingsState
    extends State<ListeningEnhancementSettings> {
  late ListeningEnhancementPreference _preference =
      widget.enhancement.preference;

  @override
  void initState() {
    super.initState();
    widget.enhancement.addListener(_sync);
  }

  @override
  void didUpdateWidget(ListeningEnhancementSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.enhancement, widget.enhancement)) {
      oldWidget.enhancement.removeListener(_sync);
      widget.enhancement.addListener(_sync);
      _preference = widget.enhancement.preference;
    }
  }

  @override
  void dispose() {
    widget.enhancement.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final current = widget.enhancement.preference;
    if (current == _preference) return;
    setState(() => _preference = current);
  }

  void _commit(ListeningEnhancementPreference value) {
    setState(() => _preference = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final preference = _preference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '声音增强',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                preference.summary,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Expanded(child: Text('音量倍率')),
            Text(
              '${preference.volumePercent}%',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final percent in const [100, 150, 200])
              ChoiceChip(
                key: ValueKey('listening-volume-$percent'),
                label: Text('$percent%'),
                selected: preference.volumePercent == percent,
                onSelected: (selected) {
                  if (!selected) return;
                  _commit(preference.copyWith(volumePercent: percent));
                },
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text(
            preference.volumePercent > 100
                ? '200% 为真实 +6 dB 增益：在线音色在合成端提升，系统音色在播放端提升。'
                : '100% 为原始音量。最高 200%，不是只改界面数字。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.5,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ListeningEnhancementMode.values)
              ChoiceChip(
                key: ValueKey('listening-enhancement-${mode.name}'),
                label: Text(mode.label),
                selected: preference.mode == mode,
                onSelected: (selected) {
                  if (!selected) return;
                  _commit(preference.copyWith(mode: mode));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          preference.mode.description,
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('listening-enhancement-normalize'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('音量均衡'),
          subtitle: Text(
            '压平忽大忽小的段落音量',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          value: preference.normalize,
          onChanged: (value) => _commit(preference.copyWith(normalize: value)),
        ),
      ],
    );
  }
}
