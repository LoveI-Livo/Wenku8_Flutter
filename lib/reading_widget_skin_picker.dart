import 'package:flutter/material.dart';

import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

/// Horizontal skin chooser for the reading widget editor.
///
/// The caller supplies [previewBuilder] so each tile can render the same card
/// the user is configuring. Selection is optimistic: [onChanged] is invoked and
/// the parent decides how to persist it, exactly like the other appearance
/// controls on the settings page.
class ReadingWidgetSkinPicker extends StatelessWidget {
  const ReadingWidgetSkinPicker({
    super.key,
    required this.value,
    required this.size,
    required this.snapshot,
    required this.previewBuilder,
    this.onChanged,
    this.tileHeight = 168,
  });

  final ReadingWidgetSkin value;
  final ReadingDesktopSize size;
  final ReadingWidgetSnapshot snapshot;
  final Widget Function(ReadingWidgetSkin skin) previewBuilder;
  final ValueChanged<ReadingWidgetSkin>? onChanged;
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final today = snapshot.verifiedTodaySeconds;
    final summary = today == null
        ? '${size.label} · ${value.description} · 今日尚未记录'
        : '${size.label} · ${value.description} · 今日 ${widgetMinutes(today)} 分钟';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: tileHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: ReadingWidgetSkin.values.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final skin = ReadingWidgetSkin.values[index];
              return _ReadingWidgetSkinTile(
                skin: skin,
                selected: skin == value,
                enabled: enabled,
                width: 208,
                onTap: enabled
                    ? () {
                        onChanged?.call(skin);
                      }
                    : null,
                preview: previewBuilder(skin),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _ReadingWidgetSkinTile extends StatelessWidget {
  const _ReadingWidgetSkinTile({
    required this.skin,
    required this.selected,
    required this.enabled,
    required this.width,
    required this.onTap,
    required this.preview,
  });

  final ReadingWidgetSkin skin;
  final bool selected;
  final bool enabled;
  final double width;
  final VoidCallback? onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = colors.primary;
    final borderColor = selected
        ? accent
        : colors.outlineVariant.withValues(alpha: enabled ? 0.9 : 0.4);
    final fillColor = selected
        ? colors.primaryContainer.withValues(alpha: 0.35)
        : colors.surfaceContainerHighest.withValues(alpha: 0.35);
    return Semantics(
      label: skin.label,
      hint: skin.description,
      button: true,
      selected: selected,
      enabled: enabled,
      child: SizedBox(
        width: width,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: IgnorePointer(child: preview),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            skin.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected ? accent : colors.onSurface,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: accent,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
