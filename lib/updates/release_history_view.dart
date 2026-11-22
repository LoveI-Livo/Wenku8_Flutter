import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import 'mod_release_history.dart';

class ReleaseHistoryView extends StatefulWidget {
  const ReleaseHistoryView({super.key});

  @override
  State<ReleaseHistoryView> createState() => _ReleaseHistoryViewState();
}

class _ReleaseHistoryViewState extends State<ReleaseHistoryView> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < modReleaseHistory.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          ContentPanel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
                  onTap: () {
                    AppHaptics.play(context, HapticCue.selection);
                    setState(() => _open = _open == index ? null : index);
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
                                    'v${modReleaseHistory[index].version}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    modReleaseHistory[index].date,
                                    style: TextStyle(fontSize: 11, color: muted),
                                  ),
                                  if (index == 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withValues(alpha: .10),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '当前',
                                        style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                modReleaseHistory[index].summary,
                                style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _open == index ? .5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : NovelMotion.contact,
                          child: const ArchiveIcon(CupertinoIcons.chevron_down, size: 16),
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
                  child: _open == index
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Divider(height: 18, color: theme.dividerColor.withValues(alpha: .5)),
                              for (final change in modReleaseHistory[index].changes)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text('•', style: TextStyle(color: theme.colorScheme.primary)),
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
          ),
        ],
      ],
    );
  }
}
