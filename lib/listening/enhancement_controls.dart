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

  /// Drag feedback stays local so the controller only saves once per commit.
  void _preview(ListeningEnhancementPreference value) {
    if (value == _preference) return;
    setState(() => _preference = value);
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
    final active = preference.mode != ListeningEnhancementMode.off;
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
        if (active) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(child: Text('音量提升')),
              Text(
                preference.gain <= 0
                    ? '不额外提升'
                    : '+${preference.gain.toStringAsFixed(0)} dB',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          Slider(
            key: const ValueKey('listening-enhancement-gain'),
            value: preference.gain
                .clamp(0.0, listeningEnhancementMaximumGain)
                .toDouble(),
            min: 0,
            max: listeningEnhancementMaximumGain,
            divisions: listeningEnhancementMaximumGain.round(),
            label: '+${preference.gain.toStringAsFixed(0)} dB',
            onChanged: (value) => _preview(preference.copyWith(gain: value)),
            onChangeEnd: (value) => _commit(preference.copyWith(gain: value)),
          ),
        ],
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
