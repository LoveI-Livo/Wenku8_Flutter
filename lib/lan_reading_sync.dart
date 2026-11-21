import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'mod_edition.dart';

/// 局域网续读的公开接口。
///
/// 原始工程把这部分实现在未公开的模块里，公开快照缺少这些文件，导致工程无法构建。
/// 本改版按原有调用点补回同一套接口，但**不启用**网络发现与传输：
/// 应用照常编译、启动、阅读，只是在「设置 → 局域网续读」里说明该功能未启用。
///
/// 如果以后拿到完整实现，只需用完整文件覆盖本文件即可，调用方不需要改动。
class LanHandoffReceipt {
  const LanHandoffReceipt({this.online});

  /// 续读请求来自哪台在线设备；为空表示本机书籍。
  final String? online;
}

/// 续读请求解析后的结果：书 + 阅读位置。
class LanHandoffResolution {
  const LanHandoffResolution({required this.book, required this.position});

  final Novel book;
  final ReadingPosition position;
}

/// 与其它设备交换续读请求的服务。本构建中始终为空实现。
class LanHandoffService {
  /// 当前待处理的续读请求；没有请求时为 null。
  LanHandoffReceipt? get received => null;

  Future<LanHandoffResolution> resolveReceipt(LanHandoffReceipt receipt) =>
      Future<LanHandoffResolution>.error(
        const FormatException('局域网续读在当前构建中未启用'),
      );

  void dismissReceipt() {}
}

/// 局域网续读的持有者：管理发现、连接与请求队列。
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

  /// 当前构建是否真的启用了局域网续读。
  static const bool supported = false;

  Future<void> initialize() async {}

  void dispose() {}
}

/// 把 [LanReadingSync] 注入到桌面与设置页。
class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});

  final LanReadingSync? sync;

  static LanReadingSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanSyncScope>()?.sync;

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => sync != oldWidget.sync;
}

/// 版本信息里标注当前构建的能力，便于排查问题。
const lanSyncDisabledNotice =
    '局域网续读未启用（$modEditionName $modEditionVersion 公开源码构建）';
