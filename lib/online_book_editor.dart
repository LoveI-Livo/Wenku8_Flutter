import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'legacy_cover.dart';
import 'book_categories.dart';
import 'catalog.dart';
import 'cloud_parse_service.dart';
import 'feature_pages.dart' show FeatureEntry, FeatureError, featurePadding;
import 'library_state.dart';
import 'local_book_edit_widgets.dart';
import 'local_book_tags_editor.dart';
import 'local_library_preferences.dart';

/// Edits metadata for a book that is read directly from a cloud drive or a
/// book source. No file is copied to the device; only the shelf record changes.
class OnlineBookEditor extends StatefulWidget {
  const OnlineBookEditor({
    super.key,
    required this.book,
    required this.library,
  });

  final Novel book;
  final LibraryState library;

  @override
  State<OnlineBookEditor> createState() => _OnlineBookEditorState();
}

class _OnlineBookEditorState extends State<OnlineBookEditor> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _summary = TextEditingController(text: widget.book.summary);
  late List<String> _tags = widget.book.tags;
  late String? _coverUrl = widget.book.coverUrl;
  String? get _originalCoverUrl => widget.book.coverUrl;
  Uint8List? _coverBytes;
  bool _coverChanged = false;
  LocalLibraryPreferences? _groups;
  String _group = LocalLibraryPreferences.unfiled;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _summary.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final groups = widget.library.organization;
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _group = groups.groupOf(widget.book.id);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '分类读取失败，请返回后重试');
    }
  }

  Future<void> _chooseCover() async {
    if (_busy) return;
    final documents = BookDocuments();
    BookDocumentSelection? selected;
    try {
      selected = await documents.pickImage();
      if (selected == null) return;
      final bytes = await File(selected.path!).readAsBytes();
      if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
        throw const FormatException('封面不能为空或超过 4 MiB');
      }
      LegacyCover.forget(widget.book.id);
      setState(() {
        _coverBytes = bytes;
        _coverChanged = true;
      });
    } catch (error) {
      if (mounted) {
        showNovelFeedback(
          context,
          error is FormatException ? error.message : '封面读取失败，请重新选择',
        );
      }
    } finally {
      if (selected != null) await documents.releaseBooks([selected]);
    }
  }

  void _removeCover() {
    LegacyCover.forget(widget.book.id);
    setState(() {
      _coverBytes = null;
      _coverUrl = null;
      _coverChanged = true;
    });
  }

  Future<void> _chooseGroup() async {
    final groups = _groups;
    if (groups == null) return;
    final value = await chooseBookCategory(
      context,
      groups,
      bookId: widget.book.id,
      reduceMotion: widget.library.reduceMotion,
    );
    if (mounted && value != null) setState(() => _group = value);
  }

  Future<void> _save() async {
    if (_busy || _groups == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final title = _title.text.trim();
    final author = _author.text.trim();
    if (title.isEmpty || author.isEmpty) {
      setState(() => _error = '书名和作者不能为空');
      showNovelFeedback(context, '书名和作者不能为空');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groups = _groups!;
      if (_group != LocalLibraryPreferences.unfiled &&
          !groups.groups.containsKey(_group)) {
        throw const FormatException('分类已变化，请重新选择分类');
      }
      var coverUrl = _coverUrl;
      if (_coverChanged) {
        if (_coverBytes != null) {
          setState(() => _error = '正在上传封面到云端…');
          coverUrl = await CloudParseService.instance.uploadCover(
            widget.book.id,
            _coverBytes!,
          );
          LegacyCover.forget(widget.book.id);
          _coverUrl = coverUrl;
        } else {
          coverUrl = null;
        }
      }
      final updated = widget.book.withMetadata(
        title: title,
        author: author,
        genre: _tags.join(' '),
        summary: _summary.text.trim(),
        coverUrl: coverUrl,
        resetCover:
            _coverChanged && coverUrl == null && _originalCoverUrl != null,
      );
      await widget.library.rememberNovel(updated);
      await widget.library.setShelfMembership(
        updated.id,
        widget.library.contains(updated.id),
        novel: updated,
      );
      await groups.assign(updated.id, _group);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        final message = e is FormatException ? e.message : '书籍信息保存未完成，请重试';
        setState(() {
          _busy = false;
          _error = message;
        });
        showNovelFeedback(context, message);
      }
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.library.setShelfMembership(
        widget.book.id,
        false,
        novel: widget.book,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '移出书架未完成，请重试';
        });
        showNovelFeedback(context, _error!);
      }
    }
  }

  Widget _identity() => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _coverBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(ArchiveDesign.coverRadius),
              child: Image.memory(
                _coverBytes!,
                width: 88,
                height: 124,
                fit: BoxFit.cover,
              ),
            )
          : NovelCover(
              widget.book.withMetadata(
                coverUrl: _coverUrl,
                resetCover: _coverUrl == null,
              ),
              width: 88,
              height: 124,
            ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              widget.book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 7),
            AppText(
              '${widget.book.sourceLabel ?? '在线书籍'} · 在线阅读',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                GlassTextButton(
                  key: const ValueKey('online-edit-cover'),
                  compact: true,
                  onPressed: _busy ? null : _chooseCover,
                  child: AppText('更换封面'),
                ),
                if (_coverChanged ||
                    (_coverUrl != null && _coverUrl != _originalCoverUrl))
                  GlassTextButton(
                    key: const ValueKey('online-edit-cover-remove'),
                    compact: true,
                    onPressed: _busy ? null : _removeCover,
                    child: const AppText('删除自选封面'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            AppText(
              '这本书不在本机保存文件，修改只更新书架信息与阅读记录。'
              '更换封面会上传到云端解析主机，本机只保存图片地址，不占用本地空间。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _content() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _identity(),
      const SizedBox(height: 30),
      const ArchiveSection(title: '书籍信息', code: '01 / ONLINE PROFILE'),
      const SizedBox(height: 18),
      LocalBookEditField(
        label: '书名',
        controller: _title,
        inputKey: const ValueKey('online-edit-书名'),
        enabled: !_busy,
      ),
      const SizedBox(height: 20),
      LocalBookEditField(
        label: '作者',
        controller: _author,
        inputKey: const ValueKey('online-edit-作者'),
        enabled: !_busy,
      ),
      const SizedBox(height: 20),
      LocalBookTagsEditor(
        value: _tags,
        availableTags: [
          for (final id in {
            ...widget.library.shelf,
            ...widget.library.readingPositions.keys,
          })
            ...?widget.library.cachedNovel(id)?.tags,
        ],
        enabled: !_busy,
        reduceMotion: widget.library.reduceMotion,
        onChanged: (tags) => setState(() => _tags = tags),
      ),
      const SizedBox(height: 20),
      LocalBookEditField(
        label: '简介',
        controller: _summary,
        inputKey: const ValueKey('online-edit-简介'),
        enabled: !_busy,
        maxLength: 5000,
        minLines: 3,
        maxLines: 6,
      ),
      const SizedBox(height: 20),
      AppText(
        '作者、简介和封面会在加入书架或首次打开时从原文件自动识别；'
        '原文件始终留在网盘，不会保存到本机。',
        style: TextStyle(
          fontSize: 12,
          height: 1.55,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 24),
      FeatureEntry(
        key: const ValueKey('online-edit-category'),
        title: '书籍分类',
        subtitle: _groups?.nameOf(_group) ?? '正在读取分类',
        icon: CupertinoIcons.folder,
        onTap: _busy || _groups == null ? null : _chooseGroup,
      ),
      const SizedBox(height: 30),
      const ArchiveSection(title: '在线阅读', code: '02 / SOURCE'),
      const SizedBox(height: 18),
      FeatureEntry(
        key: const ValueKey('online-edit-source'),
        title: '内容来源',
        subtitle: '${widget.book.sourceLabel ?? '在线书籍'} · 点开书即从原网盘在线读取，不下载到本机',
        icon: CupertinoIcons.cloud,
        onTap: null,
      ),
      const SizedBox(height: 12),
      FeatureEntry(
        key: const ValueKey('online-edit-reader'),
        title: '阅读设置',
        subtitle: '字号、行距、字体、主题和阅读方向在阅读器右上角的设置面板中调整',
        icon: CupertinoIcons.slider_horizontal_3,
        onTap: null,
      ),
      if (widget.library.contains(widget.book.id)) ...[
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: GlassTextButton(
            key: const ValueKey('online-edit-remove'),
            compact: true,
            onPressed: _busy ? null : _remove,
            child: AppText(
              '移出书架（保留阅读进度）',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
      FeatureError(_error),
    ],
  );

  @override
  Widget build(BuildContext context) => LocalBookEditLayout(
    title: '书籍设置',
    code: 'ONLINE / BOOK PROFILE',
    onBack: _busy ? null : () => Navigator.pop(context),
    primaryKey: const ValueKey('online-edit-save'),
    primaryLabel: _busy ? '正在保存' : '保存修改',
    primaryIcon: CupertinoIcons.checkmark,
    onPrimary: _busy || _groups == null ? null : _save,
    secondaryLabel: '取消',
    secondaryIcon: CupertinoIcons.xmark,
    onSecondary: _busy ? null : () => Navigator.pop(context),
    slivers: [
      SliverPadding(
        padding: featurePadding(context).copyWith(bottom: 12),
        sliver: SliverToBoxAdapter(child: _content()),
      ),
    ],
  );
}
