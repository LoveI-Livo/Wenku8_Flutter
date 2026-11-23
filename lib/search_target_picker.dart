import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_search_field.dart';
import 'app_ui.dart';
import 'cloud_catalog_search.dart';

/// 书源/网盘很多时，弹出菜单放不下几千项；这里用可搜索、懒加载的列表页。
class SearchTargetPickerPage extends StatefulWidget {
  const SearchTargetPickerPage({
    super.key,
    required this.targets,
    this.selectedKey,
  });
  final List<CloudSearchTarget> targets;
  final String? selectedKey;

  @override
  State<SearchTargetPickerPage> createState() => _SearchTargetPickerPageState();
}

class _SearchTargetPickerPageState extends State<SearchTargetPickerPage> {
  final _query = TextEditingController();
  List<CloudSearchTarget> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.targets;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _filter(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.targets
          : widget.targets
                .where(
                  (target) =>
                      target.label.toLowerCase().contains(query) ||
                      (target.url ?? '').toLowerCase().contains(query),
                )
                .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回',
            onPressed: () => Navigator.pop(context),
          ),
          title: ArchiveRouteTitle(
            title: '选择搜索来源',
            code: '${widget.targets.length} SOURCES',
          ),
        ),
        body: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 16,
            24,
            MediaQuery.paddingOf(context).bottom + 28,
          ),
          itemCount: _filtered.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ContentPanel(
                    child: AppSearchField(
                      controller: _query,
                      hint: '搜索书源名称或地址',
                      onChanged: _filter,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _targetRow(
                    context,
                    label: '全部来源',
                    subtitle: '依次扫描当前范围里的所有来源',
                    selected: widget.selectedKey == null,
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }
            if (index == _filtered.length + 1) {
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AppText(
                  '共 ${_filtered.length} 个来源',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final target = _filtered[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _targetRow(
                context,
                key: ValueKey('target-picker-${target.key}'),
                label: target.label,
                subtitle: target.url ?? '',
                selected: widget.selectedKey == target.key,
                onTap: () => Navigator.pop(context, target.key),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _targetRow(
    BuildContext context, {
    Key? key,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) => ContentPanel(
    key: key,
    child: InkWell(
      borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
      onTap: () {
        AppHaptics.play(context, HapticCue.selection);
        onTap();
      },
      child: Row(
        children: [
          ArchiveIcon(
            selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
            size: 20,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  AppText(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
