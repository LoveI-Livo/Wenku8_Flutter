import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_search_field.dart';
import 'app_ui.dart';
import 'cloud_catalog_search.dart';

/// 书源/网盘很多时，弹出菜单放不下几千项；这里用可搜索、懒加载的列表页，
/// 并改成多选：每一项前面都有勾，选完点底部确认再统一搜索。
class SearchTargetPickerPage extends StatefulWidget {
  const SearchTargetPickerPage({
    super.key,
    required this.targets,
    this.selectedKeys = const {},
  });
  final List<CloudSearchTarget> targets;
  final Set<String> selectedKeys;

  @override
  State<SearchTargetPickerPage> createState() => _SearchTargetPickerPageState();
}

class _SearchTargetPickerPageState extends State<SearchTargetPickerPage> {
  final _query = TextEditingController();
  List<CloudSearchTarget> _filtered = const [];
  late final Set<String> _selected = {...widget.selectedKeys};

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

  void _toggle(String key) {
    AppHaptics.play(context, HapticCue.selection);
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  void _selectAllVisible() {
    AppHaptics.play(context, HapticCue.selection);
    setState(() => _selected.addAll(_filtered.map((target) => target.key)));
  }

  @override
  Widget build(BuildContext context) {
    final all = _selected.isEmpty;
    return Scaffold(
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
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.paddingOf(context).top +
                        FrostedHeader.toolbarHeight +
                        16,
                    24,
                    16,
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
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              GlassPillButton(
                                key: const ValueKey('search-target-select-all'),
                                icon: CupertinoIcons.checkmark_alt,
                                label: '全选当前 ${_filtered.length} 个',
                                onPressed: _filtered.isEmpty
                                    ? null
                                    : _selectAllVisible,
                              ),
                              GlassPillButton(
                                key: const ValueKey('search-target-clear'),
                                icon: CupertinoIcons.xmark,
                                label: '清空选择',
                                onPressed: _selected.isEmpty
                                    ? null
                                    : () => setState(_selected.clear),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _targetRow(
                            context,
                            label: '全部来源',
                            subtitle: '不勾选任何来源时，搜索当前范围里的全部来源',
                            selected: all,
                            onTap: () {
                              AppHaptics.play(context, HapticCue.selection);
                              setState(_selected.clear);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    }
                    if (index == _filtered.length + 1) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: AppText(
                          '共 ${_filtered.length} 个来源，已勾选 ${_selected.length} 个',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                        selected: _selected.contains(target.key),
                        onTap: () => _toggle(target.key),
                      ),
                    );
                  },
                ),
              ),
              _confirmBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmBar(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      22 + MediaQuery.paddingOf(context).left,
      12,
      22 + MediaQuery.paddingOf(context).right,
      MediaQuery.paddingOf(context).bottom + 12,
    ),
    child: SizedBox(
      width: double.infinity,
      child: GlassPillButton(
        key: const ValueKey('search-target-confirm'),
        icon: CupertinoIcons.search,
        label: _selected.isEmpty ? '搜索全部来源' : '确认并搜索已选 ${_selected.length} 个来源',
        onPressed: () => Navigator.pop(context, <String>{..._selected}),
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
      onTap: onTap,
      child: Row(
        children: [
          AnimatedContainer(
            duration: NovelMotion.contact,
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                width: 1.4,
              ),
              color: selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .16)
                  : Colors.transparent,
            ),
            child: selected
                ? Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 15,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
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
