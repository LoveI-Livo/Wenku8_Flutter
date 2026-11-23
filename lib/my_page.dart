import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'bookmark_library_page.dart';
import 'reading_statistics_page.dart';
import 'catalog.dart';
import 'local_avatar.dart';
import 'download_center.dart';
import 'book_documents.dart';
import 'dock_layout.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'offline_repository.dart';
import 'pages.dart' show SettingsPage;
import 'ui_notifiers.dart';
import 'updates/app_updates.dart';
import 'updates/update_page.dart';
import 'wenku_features.dart';

class MyPage extends StatelessWidget {
  const MyPage({
    super.key,
    required this.state,
    required this.repository,
    this.showHeader = true,
  });
  final LibraryState state;
  final NovelRepository repository;
  final bool showHeader;

  Widget _avatarFallback(dynamic account) => account?.authenticated == true
      ? const Center(
          child: ArchiveIcon(CupertinoIcons.person_crop_circle, size: 40),
        )
      : Image.asset(
          'assets/branding/app-icon.png',
          width: 56,
          height: 56,
          fit: BoxFit.cover,
        );

  Future<void> _editAvatar(BuildContext context) async {
    LocalAvatar.instance.ensureLoaded();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.photo),
              title: const AppText('从相册选择头像'),
              subtitle: const AppText('点击即可更换，不需要登录文库账号'),
              onTap: () => Navigator.of(sheetContext).pop('pick'),
            ),
            if (LocalAvatar.instance.value != null)
              ListTile(
                leading: const Icon(CupertinoIcons.trash),
                title: const AppText('恢复默认头像'),
                onTap: () => Navigator.of(sheetContext).pop('clear'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'clear') {
      await LocalAvatar.instance.clear();
      if (context.mounted) {
        showNovelFeedback(context, '已恢复默认头像');
      }
      return;
    }
    final documents = BookDocuments();
    BookDocumentSelection? selected;
    try {
      selected = await documents.pickImage();
      if (selected == null || !context.mounted) return;
      final bytes = await File(selected.path!).readAsBytes();
      if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
        showNovelFeedback(context, '头像不能为空或超过 4 MiB');
        return;
      }
      await LocalAvatar.instance.save(bytes);
      if (context.mounted) showNovelFeedback(context, '头像已更新');
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '头像读取失败，请重新选择');
    } finally {
      if (selected != null) await documents.releaseBooks([selected]);
    }
  }

  Widget buildHeader(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: ArchiveMasthead(title: '我的', code: '05 / PERSONAL ARCHIVE'),
  );

  @override
  Widget build(BuildContext context) {
    LocalAvatar.instance.ensureLoaded();
    final features = WenkuFeaturesScope.maybeOf(context);
    final updates = AppUpdatesScope.maybeOf(context);
    return GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            key: const PageStorageKey('my-page'),
            padding: featurePadding(
              context,
            ).copyWith(bottom: DockLayout.scrollPaddingOf(context)),
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([
                  features?.account ?? state.bookmarkChanges,
                  ?features?.shelfSync,
                ]),
                builder: (context, _) {
                  final account = features?.account;
                  final profile = account?.profile;
                  return ContentPanel(
                    key: const ValueKey('my-account'),
                    onTap: account == null
                        ? null
                        : () => pushNovelPage<void>(
                            context,
                            WenkuAccountPage(
                              account: account,
                              state: state,
                              repository: repository,
                            ),
                            reduceMotion: state.reduceMotion,
                          ),
                    child: Row(
                      children: [
                        AnimatedBuilder(
                          animation: LocalAvatar.instance,
                          builder: (context, _) {
                            final local = LocalAvatar.instance.value;
                            return GestureDetector(
                              key: const ValueKey('my-avatar-edit'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _editAvatar(context),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: local != null
                                      ? Image.memory(
                                          local,
                                          fit: BoxFit.cover,
                                          cacheWidth:
                                              (56 *
                                                      MediaQuery.devicePixelRatioOf(
                                                        context,
                                                      ))
                                                  .ceil(),
                                          errorBuilder: (_, _, _) =>
                                              _avatarFallback(account),
                                        )
                                      : account?.authenticated == true &&
                                            account?.avatar != null
                                      ? Image.memory(
                                          account!.avatar!,
                                          fit: BoxFit.cover,
                                          cacheWidth:
                                              (56 *
                                                      MediaQuery.devicePixelRatioOf(
                                                        context,
                                                      ))
                                                  .ceil(),
                                          errorBuilder: (_, _, _) =>
                                              _avatarFallback(account),
                                        )
                                      : _avatarFallback(account),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                account?.authenticated == true
                                    ? profile?.displayName ?? '文库账号'
                                    : '登录文库账号',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              AppText(
                                account?.authenticated == true
                                    ? profile == null
                                          ? '账号已连接'
                                          : '${profile.score} 积分 · ${profile.rank}${features?.shelfSync == null
                                                ? ''
                                                : features!.shelfSync!.syncing
                                                ? '\n书架正在同步'
                                                : features.shelfSync!.error != null
                                                ? '\n书架待同步 · ${features.shelfSync!.error}'
                                                : features.shelfSync!.syncedAt != null
                                                ? '\n书架已与文库同步'
                                                : ''}'
                                    : account?.error ?? '轻小说文库账号 · 云书架与每日签到',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const ArchiveIcon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              FeatureEntry(
                key: const ValueKey('my-statistics'),
                title: '统计',
                subtitle: '阅读记录、藏书与书签',
                icon: CupertinoIcons.chart_bar,
                onTap: () => pushNovelPage<void>(
                  context,
                  ReadingStatisticsPage(state: state, repository: repository),
                  reduceMotion: state.reduceMotion,
                ),
              ),
              const SizedBox(height: 14),
              ActiveListenableBuilder(
                listenable: state.bookmarkChanges,
                builder: (context) {
                  final count = libraryBookmarks(
                    state,
                    books: repository is OfflineNovelRepository
                        ? (repository as OfflineNovelRepository).local
                        : null,
                  ).length;
                  return FeatureEntry(
                    key: const ValueKey('my-bookmarks'),
                    title: '书签',
                    subtitle: count == 0 ? '收藏喜欢的句子与阅读位置' : '$count 条书签与摘录',
                    icon: CupertinoIcons.bookmark,
                    onTap: () => pushNovelPage<void>(
                      context,
                      BookmarkLibraryPage(state: state, repository: repository),
                      reduceMotion: state.reduceMotion,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              FeatureEntry(
                key: const ValueKey('my-downloads'),
                title: '下载',
                subtitle: '已下载小说、保存到本地文件夹与下载限速',
                icon: CupertinoIcons.arrow_down_to_line,
                onTap: () => pushNovelPage<void>(
                  context,
                  DownloadsPage(state: state, repository: repository),
                  reduceMotion: state.reduceMotion,
                ),
              ),
              const SizedBox(height: 14),
              FeatureEntry(
                key: const ValueKey('my-settings'),
                title: '设置',
                subtitle: '阅读、外观、性能与本地数据',
                icon: CupertinoIcons.settings,
                onTap: () => pushNovelPage<void>(
                  context,
                  ArchiveFeaturePage(
                    title: '设置',
                    code: 'SYSTEM / PREFERENCES',
                    child: SettingsPage(
                      state: state,
                      repository: repository,
                      showHeader: false,
                    ),
                  ),
                  reduceMotion: state.reduceMotion,
                ),
              ),
              const SizedBox(height: 14),
              FeatureEntry(
                key: const ValueKey('my-about'),
                title: '关于',
                subtitle:
                    '版本 ${updates?.installed?.version ?? currentAppVersion}${updates?.available == true ? ' · 有新版本' : ''}',
                icon: CupertinoIcons.info_circle,
                onTap: () => pushNovelPage<void>(
                  context,
                  AppUpdatePage(updates: updates),
                  reduceMotion: state.reduceMotion,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
