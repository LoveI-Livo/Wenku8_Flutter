import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import 'mod_release_history.dart';

/// 关于页版本记录按版本号的三段折叠，共三层：
/// 1. 大版本（0.x / 1.x …）；
/// 2. 次版本（0.6 / 0.7 …）；
/// 3. 单个补丁版本（0.7.6 / 0.7.5 …）。
/// 每层都保留折叠，展开大版本后看到次版本，再展开才看到具体版本。
class ReleaseHistoryView extends StatefulWidget {
  const ReleaseHistoryView({super.key});

  @override
  State<ReleaseHistoryView> createState() => _ReleaseHistoryViewState();
}

class _ReleaseHistoryViewState extends State<ReleaseHistoryView> {
  String? _openMajor;
  String? _openMinor;
  String? _openRelease;

  @override
  Widget build(BuildContext context) {
    final majors = _groupReleases(modReleaseHistory);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < majors.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _majorCard(context, majors[index], theme, muted),
        ],
      ],
    );
  }

  Widget _majorCard(
    BuildContext context,
    _MajorGroup group,
    ThemeData theme,
    Color muted,
  ) {
    final open = _openMajor == group.key;
    return ContentPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _groupHeader(
            context,
            title: '${group.key}.x 系列',
            subtitle:
                '${group.range} · ${group.releases.length} 个版本 · ${group.releases.first.summary}',
            open: open,
            current: group.current,
            theme: theme,
            muted: muted,
            onTap: () {
              AppHaptics.play(context, HapticCue.selection);
              setState(() {
                _openMajor = open ? null : group.key;
                if (!open) {
                  _openMinor = null;
                  _openRelease = null;
                }
              });
            },
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : NovelMotion.enter,
            curve: NovelMotion.settle,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 16,
                          color: theme.dividerColor.withValues(alpha: .5),
                        ),
                        for (var index = 0;
                            index < group.minors.length;
                            index++) ...[
                          if (index > 0) const SizedBox(height: 8),
                          _minorCard(
                            context,
                            group.minors[index],
                            theme,
                            muted,
                          ),
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

  Widget _minorCard(
    BuildContext context,
    _MinorGroup group,
    ThemeData theme,
    Color muted,
  ) {
    final open = _openMinor == group.key;
    return ContentPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _groupHeader(
            context,
            title: '${group.key} 系列',
            subtitle:
                '${group.range} · ${group.releases.length} 个版本 · ${group.releases.first.summary}',
            open: open,
            current: group.current,
            theme: theme,
            muted: muted,
            compact: true,
            onTap: () {
              AppHaptics.play(context, HapticCue.selection);
              setState(() {
                _openMinor = open ? null : group.key;
                _openRelease = null;
              });
            },
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : NovelMotion.enter,
            curve: NovelMotion.settle,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 14,
                          color: theme.dividerColor.withValues(alpha: .4),
                        ),
                        for (var index = 0;
                            index < group.releases.length;
                            index++) ...[
                          if (index > 0) const SizedBox(height: 8),
                          _releaseCard(
                            context,
                            group.releases[index],
                            theme,
                            muted,
                          ),
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

  Widget _groupHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool open,
    required bool current,
    required ThemeData theme,
    required Color muted,
    required VoidCallback onTap,
    bool compact = false,
  }) => InkWell(
    borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 12 : 14, 12, compact ? 12 : 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: .10),
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
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
            child: ArchiveIcon(
              CupertinoIcons.chevron_down,
              size: compact ? 14 : 16,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _releaseCard(
    BuildContext context,
    ModRelease release,
    ThemeData theme,
    Color muted,
  ) {
    final open = _openRelease == release.version;
    final current = release.version == modReleaseHistory.first.version;
    return ContentPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
            onTap: () {
              AppHaptics.play(context, HapticCue.selection);
              setState(() => _openRelease = open ? null : release.version);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'v${release.version}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              release.date,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                            if (current) ...[
                              const SizedBox(width: 8),
                              Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          release.summary,
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
                      size: 14,
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 12,
                          color: theme.dividerColor.withValues(alpha: .4),
                        ),
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
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _MajorGroup {
  const _MajorGroup({
    required this.key,
    required this.range,
    required this.releases,
    required this.minors,
    required this.current,
  });
  final String key, range;
  final List<ModRelease> releases;
  final List<_MinorGroup> minors;
  final bool current;
}

class _MinorGroup {
  const _MinorGroup({
    required this.key,
    required this.range,
    required this.releases,
    required this.current,
  });
  final String key, range;
  final List<ModRelease> releases;
  final bool current;
}

/// 版本号有三段，就按三段建树：0.x → 0.7 → 0.7.6。
/// 每层都保持发布顺序，新版本在前。
List<_MajorGroup> _groupReleases(List<ModRelease> releases) {
  final majors = <String, List<ModRelease>>{};
  final majorOrder = <String>[];
  final minors = <String, List<ModRelease>>{};
  final minorOrder = <String, List<String>>{};
  for (final release in releases) {
    final parts = release.version.split('.');
    final major = parts.isNotEmpty ? parts[0] : release.version;
    final minor = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : release.version;
    if (!majors.containsKey(major)) {
      majors[major] = [];
      majorOrder.add(major);
      minorOrder[major] = [];
    }
    majors[major]!.add(release);
    if (!minors.containsKey(minor)) {
      minors[minor] = [];
      minorOrder[major]!.add(minor);
    }
    minors[minor]!.add(release);
  }
  final currentVersion = releases.isEmpty ? '' : releases.first.version;
   return [
    for (final major in majorOrder)
      _MajorGroup(
        key: major,
        range: '${majors[major]!.last.version} – ${majors[major]!.first.version}',
        releases: majors[major]!,
        minors: [
          for (final minor in minorOrder[major]!)
            _MinorGroup(
              key: minor,
              range: '${minors[minor]!.last.version} – ${minors[minor]!.first.version}',
              releases: minors[minor]!,
              current: currentVersion.startsWith('$minor.'),
            ),
        ],
        current: currentVersion.startsWith('$major.'),
      ),
  ];
}
