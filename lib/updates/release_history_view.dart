import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import 'mod_release_history.dart';

/// 关于页按“大版本”折叠：0.6.x 一组、0.7.x 一组、0.8.x 一组。
/// 组内所有小版本直接平铺，不再为每个小版本各做一次折叠，避免列表越滑越长。
class ReleaseHistoryView extends StatefulWidget {
  const ReleaseHistoryView({super.key});

  @override
  State<ReleaseHistoryView> createState() => _ReleaseHistoryViewState();
}

class _ReleaseHistoryViewState extends State<ReleaseHistoryView> {
  String? _openGroup;

  @override
  Widget build(BuildContext context) {
    final groups = _groupReleases(modReleaseHistory);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _groupCard(context, groups[index], theme, muted),
        ],
      ],
    );
  }

  Widget _groupCard(
    BuildContext context,
    _ReleaseGroup group,
    ThemeData theme,
    Color muted,
  ) {
    final open = _openGroup == group.key;
    return ContentPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
            onTap: () {
              AppHaptics.play(context, HapticCue.selection);
              setState(() => _openGroup = open ? null : group.key);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${group.label} 系列',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            if (group.current) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: .10,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '当前',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${group.range} · ${group.releases.length} 个版本 · ${group.releases.first.summary}',
                          style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: open ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : NovelMotion.contact,
                    child: const ArchiveIcon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : NovelMotion.enter,
            curve: NovelMotion.settle,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 18,
                          color: theme.dividerColor.withValues(alpha: .5),
                        ),
                        for (var index = 0;
                            index < group.releases.length;
                            index++) ...[
                          if (index > 0)
                            Divider(
                              height: 24,
                              color: theme.dividerColor.withValues(alpha: .35),
                            ),
                          _releaseBlock(context, group.releases[index], theme, muted),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _releaseBlock(
    BuildContext context,
    ModRelease release,
    ThemeData theme,
    Color muted,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            'v${release.version}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Text(release.date, style: TextStyle(fontSize: 11, color: muted)),
          if (release.version == modReleaseHistory.first.version) ...[
            const SizedBox(width: 8),
            Text(
              '当前',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
            ),
          ],
        ],
      ),
      const SizedBox(height: 5),
      Text(
        release.summary,
        style: TextStyle(fontSize: 12, height: 1.5, color: muted),
      ),
      const SizedBox(height: 10),
      for (final change in release.changes)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '•',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  change,
                  style: const TextStyle(fontSize: 13, height: 1.65),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ReleaseGroup {
  const _ReleaseGroup({
    required this.key,
    required this.label,
    required this.range,
    required this.releases,
    required this.current,
  });
  final String key, label, range;
  final List<ModRelease> releases;
  final bool current;
}

/// 以主版本号 + 次版本号分组：0.6.0–0.6.10 归到 0.6，0.7.x 归到 0.7。
/// 组保持发布顺序（新版本在前），组内也保持新版本在前。
List<_ReleaseGroup> _groupReleases(List<ModRelease> releases) {
  final map = <String, List<ModRelease>>{};
  final order = <String>[];
  for (final release in releases) {
    final parts = release.version.split('.');
    final key = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : release.version;
    if (!map.containsKey(key)) {
      map[key] = [];
      order.add(key);
    }
    map[key]!.add(release);
  }
  final currentVersion = releases.isEmpty ? '' : releases.first.version;
  return [
    for (final key in order)
      _ReleaseGroup(
        key: key,
        label: key,
        range: '${map[key]!.last.version} – ${map[key]!.first.version}',
        releases: map[key]!,
        current: currentVersion.startsWith('$key.'),
      ),
  ];
}
