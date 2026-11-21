import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'local_books.dart';

/// 打开「批量整理本地书」。
///
/// 原工程的批量整理页面属于未公开模块，公开快照里缺失。
/// 这里补回入口与页面骨架：列出本机书籍并提供说明，
/// 保证书架上的「批量整理本地书」按钮不会点到就崩。
Future<void> openLocalBookBatch(
  BuildContext context, {
  required LocalBookStore books,
  required LibraryState library,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => LocalBookBatchPage(books: books, library: library),
  ),
);

class LocalBookBatchPage extends StatelessWidget {
  const LocalBookBatchPage({
    super.key,
    required this.books,
    required this.library,
  });

  final LocalBookStore books;
  final LibraryState library;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final items = books.books;
    return ArchiveFeaturePage(
      title: '批量整理本地书',
      code: 'LOCAL / BATCH',
      child: ListView.builder(
        key: const PageStorageKey('local-batch'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppText(
                      '共 ${items.length} 本本地书',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      '批量选择与批量改名/移除功能依赖原工程未公开的模块，'
                      '当前构建只提供清单查看；单本编辑请回到本地书库逐本操作。',
                      style: TextStyle(fontSize: 12, height: 1.7, color: muted),
                    ),
                  ],
                ),
              ),
            );
          }
          final book = items[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ContentPanel(
              child: Row(
                children: [
                  const ArchiveIcon(CupertinoIcons.book, size: 19),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          book.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        AppText(
                          '${book.author} · ${book.chapters.length} 章',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
