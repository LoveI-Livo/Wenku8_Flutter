import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';

/// 局域网续读的公开接口：类型齐全，但不启用网络发现。
class LanHandoffReceipt {
  const LanHandoffReceipt({this.online});

  final String? online;
}

class LanHandoffResolution {
  const LanHandoffResolution({required this.book, required this.position});

  final Novel book;
  final ReadingPosition position;
}

class LanHandoffService {
  LanHandoffReceipt? get received => null;

  Future<LanHandoffResolution> resolveReceipt(LanHandoffReceipt receipt) =>
      Future<LanHandoffResolution>.error(
        const FormatException('局域网续读在当前构建中未启用'),
      );

  void dismissReceipt() {}
}

class LanReadingSync {
  LanReadingSync({
    required this.state,
    required this.preferences,
    required this.books,
    required this.repository,
  });

  final LibraryState state;
  final SharedPreferences preferences;
  final LocalBookStore? books;
  final NovelRepository repository;

  final LanHandoffService handoff = LanHandoffService();

  static const bool supported = false;

  Future<void> initialize() async {}

  void dispose() {}
}

class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});

  final LanReadingSync? sync;

  static LanReadingSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanSyncScope>()?.sync;

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => sync != oldWidget.sync;
}
