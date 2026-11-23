import 'package:flutter/foundation.dart';

import 'library_state.dart';
import 'network_status.dart';

/// Stable page identities: changing dock membership never renumbers the pages
/// or disposes their reading/search/scroll state.
class HomeNavigation extends ChangeNotifier {
  HomeNavigation(this.preferences, this.network) {
    preferences.navigationChanges.addListener(_changed);
    network?.addListener(_changed);
    _value = _read();
  }

  final LibraryState preferences;
  final NetworkStatus? network;
  late ({bool localReader, bool cachedShelf, bool combinedShelf}) _value;

  ({bool localReader, bool cachedShelf, bool combinedShelf}) _read() => (
    localReader: preferences.localReaderMode,
    cachedShelf: preferences.adaptWhenOffline && (network?.offline ?? false),
    combinedShelf: preferences.combinedShelf,
  );

  bool get cachedShelf => _value.cachedShelf;
  bool get localReader => _value.localReader;
  bool get combinedShelf => _value.combinedShelf;
  bool get readableShelfOnly => cachedShelf || localReader;
  List<int> get tabs {
    // 0 发现 / 1 书架 / 2 本地 / 3 网络 / 4 我的。网络书架始终保留，
    // 它和普通书架共用同一套功能，只是数据范围限定为网盘和小说书源。
    final base = localReader
        ? (combinedShelf ? const [1, 3, 4] : const [2, 3, 4])
        : combinedShelf
        ? (cachedShelf ? const [1, 3, 4] : const [0, 1, 3, 4])
        : (cachedShelf ? const [1, 2, 3, 4] : const [0, 1, 2, 3, 4]);
    final visible = base
        .where((tab) => tab == 4 || preferences.dockTabVisible(tab))
        .toList();
    if (!visible.contains(4)) visible.add(4);
    return visible.isEmpty ? const [4] : visible;
  }

  int destination(int current) {
    final visible = tabs;
    if (visible.contains(current)) return current;
    if (localReader && visible.contains(combinedShelf ? 1 : 2)) {
      return combinedShelf ? 1 : 2;
    }
    if (visible.contains(1)) return 1;
    return visible.first;
  }

  void _changed() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    preferences.navigationChanges.removeListener(_changed);
    network?.removeListener(_changed);
    super.dispose();
  }
}
