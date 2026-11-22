import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';

/// A reading position offered by another device on the same Wi-Fi.
class LanHandoffReceipt {
  const LanHandoffReceipt({
    required this.deviceId,
    required this.deviceName,
    required this.bookId,
    required this.title,
    required this.author,
    required this.position,
    this.online,
  });

  final String deviceId;
  final String deviceName;
  final int bookId;
  final String title;
  final String author;
  final ReadingPosition position;
  final String? online;
}

class LanHandoffResolution {
  const LanHandoffResolution({required this.book, required this.position});

  final Novel book;
  final ReadingPosition position;
}

/// Receives and exposes one pending handoff. Extends [ChangeNotifier] so the
/// in-app notice can appear without polling.
class LanHandoffService extends ChangeNotifier {
  LanHandoffService({this.state, this.books, this.repository});

  final LibraryState? state;
  final LocalBookStore? books;
  final NovelRepository? repository;
  LanHandoffReceipt? _received;
  LanHandoffReceipt? get received => _received;

  void offer(LanHandoffReceipt receipt) {
    if (_received?.deviceId == receipt.deviceId &&
        _received?.bookId == receipt.bookId &&
        _received?.position.updatedAt == receipt.position.updatedAt) {
      return;
    }
    _received = receipt;
    notifyListeners();
  }

  Future<LanHandoffResolution> resolveReceipt(LanHandoffReceipt receipt) async {
    final source = state;
    final store = books;
    final repo = repository;
    Novel? book =
        source?.cachedNovel(receipt.bookId) ?? store?.book(receipt.bookId);
    if (book == null && repo != null) {
      try {
        book = await repo.find(receipt.bookId);
      } catch (_) {}
    }
    if (book == null) {
      throw const FormatException('另一台设备传的是这本书，但本机没有这份书源；请先导入同一本书');
    }
    var resolved = book;
    if (resolved.chapters.isEmpty && repo != null) {
      try {
        final chapters = await repo.chapters(receipt.bookId);
        if (chapters.isNotEmpty) resolved = resolved.withChapters(chapters);
      } catch (_) {}
    }
    if (resolved.chapters.isEmpty) {
      throw const FormatException('这本书的章节尚未准备好，请先在本机打开一次');
    }
    final chapterCount = resolved.chapters.length;
    var chapter = receipt.position.chapter;
    if (chapter < 0 || chapter >= chapterCount) chapter = 0;
    return LanHandoffResolution(
      book: resolved,
      position: ReadingPosition(
        chapter: chapter,
        chapterId: resolved.chapters[chapter].id,
        offset: receipt.position.offset,
        fraction: receipt.position.fraction,
        fontSize: receipt.position.fontSize,
        width: receipt.position.width,
        updatedAt: receipt.position.updatedAt,
        lineHeight: receipt.position.lineHeight,
        paragraphIndex: receipt.position.paragraphIndex,
        paragraphFraction: receipt.position.paragraphFraction,
        textOffset: receipt.position.textOffset,
        textScale: receipt.position.textScale,
        typeface: receipt.position.typeface,
        layout: receipt.position.layout,
        contentRevision: receipt.position.contentRevision,
      ),
    );
  }

  Future<void> consider(LanHandoffReceipt receipt) async {
    try {
      final source = state;
      final store = books;
      final repo = repository;
      Novel? book =
          source?.cachedNovel(receipt.bookId) ?? store?.book(receipt.bookId);
      if (book == null && repo != null) book = await repo.find(receipt.bookId);
      if (book == null) return;
      offer(receipt);
    } catch (_) {}
  }

  void dismissReceipt() {
    if (_received == null) return;
    _received = null;
    notifyListeners();
  }
}

/// Local-network handoff over UDP broadcast. No account, relay or cloud service
/// is involved: devices on the same Wi-Fi exchange one small JSON packet.
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

  late final LanHandoffService handoff = LanHandoffService(
    state: state,
    books: books,
    repository: repository,
  );
  static const bool supported = true;
  static const int port = 45871;
  static const String _appTag = 'qingxiaoshuo-lan-v1';
  static const String enabledKey = 'lan_reading_enabled_v1';
  static const String _deviceKey = 'lan_reading_device_id_v1';
  static const String _nameKey = 'lan_reading_device_name_v1';

  RawDatagramSocket? _socket;
  Timer? _expiry;
  String _deviceId = '';
  String _deviceName = '';

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  bool get listening => _socket != null;

  Future<void> prepareIdentity() async {
    _deviceId =
        preferences.getString(_deviceKey) ??
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 30).toRadixString(36)}';
    if (preferences.getString(_deviceKey) == null) {
      await preferences.setString(_deviceKey, _deviceId);
    }
    _deviceName = preferences.getString(_nameKey)?.trim().isNotEmpty == true
        ? preferences.getString(_nameKey)!.trim()
        : '我的设备';
  }

  /// Starts listening only after the user explicitly enables LAN sync. The
  /// platform permission sheet is requested before the UDP socket is bound.
  Future<bool> enable() async {
    if (_socket != null) {
      await preferences.setBool(enabledKey, true);
      return true;
    }
    final granted = await LanPermissionBridge.requestLocalNetwork();
    if (!granted) return false;
    await initialize();
    if (_socket == null) return false;
    await preferences.setBool(enabledKey, true);
    return true;
  }

  Future<void> disable() async {
    await preferences.setBool(enabledKey, false);
    _expiry?.cancel();
    _socket?.close();
    _socket = null;
    _expiry = null;
  }

  /// Used at app start: restore the saved state without showing a permission
  /// sheet on launch. The sheet is only triggered by [enable].
  Future<void> restore() async {
    await prepareIdentity();
    if (preferences.getBool(enabledKey) ?? false) await initialize();
  }

  Future<void> initialize() async {
    await prepareIdentity();
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onPacket, onError: (_) {});
    } catch (_) {
      _socket = null;
    }
  }

  void _onPacket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null || datagram.data.length > 48 * 1024) return;
    try {
      final raw = jsonDecode(utf8.decode(datagram.data));
      if (raw is! Map || raw['app'] != _appTag || raw['v'] != 1) return;
      final id = raw['deviceId'];
      if (id is! String || id == _deviceId) return;
      final book = raw['book'];
      final position = raw['position'];
      if (book is! Map || position is! Map<String, dynamic>) return;
      final bookId = book['id'];
      if (bookId is! int) return;
      final parsed = ReadingPosition.fromJson(position);
      final receipt = LanHandoffReceipt(
        deviceId: id,
        deviceName:
            raw['deviceName'] is String &&
                (raw['deviceName'] as String).trim().isNotEmpty
            ? (raw['deviceName'] as String).trim()
            : '附近的设备',
        bookId: bookId,
        title: book['title'] is String ? book['title'] as String : '',
        author: book['author'] is String ? book['author'] as String : '',
        position: parsed,
        online: book['online'] is String ? book['online'] as String : null,
      );
      unawaited(handoff.consider(receipt));
      _expiry?.cancel();
      _expiry = Timer(const Duration(minutes: 10), handoff.dismissReceipt);
    } catch (_) {
      // Ignore unrelated or malformed broadcasts from other apps.
    }
  }

  Future<bool> send(Novel book, ReadingPosition position) async {
    final socket = _socket;
    if (socket == null) return false;
    final payload = utf8.encode(
      jsonEncode({
        'app': _appTag,
        'v': 1,
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'book': {
          'id': book.id,
          'title': book.title,
          'author': book.author,
          if (book.remoteUrl != null) 'online': book.remoteUrl,
        },
        'position': position.toJson(),
      }),
    );
    var sent = false;
    for (var i = 0; i < 5; i++) {
      try {
        socket.send(payload, InternetAddress('255.255.255.255'), port);
        sent = true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    return sent;
  }

  void dispose() {
    _expiry?.cancel();
    _socket?.close();
    _socket = null;
    handoff.dispose();
  }
}

/// Wraps the small native bridge that makes the platform show its own local
/// network permission sheet. iOS uses a Bonjour browser; Android requests the
/// runtime permission from the current activity.
abstract final class LanPermissionBridge {
  static const _android = MethodChannel('org.mewx.wenku8/lan_permission');
  static const _ios = MethodChannel('org.mewx.wenku8/lan_discovery');

  static Future<bool> requestLocalNetwork() async {
    final channel = Platform.isAndroid ? _android : _ios;
    try {
      return await channel.invokeMethod<bool>('requestLocalNetwork') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }
}

class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});

  final LanReadingSync? sync;

  static LanReadingSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanSyncScope>()?.sync;

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => sync != oldWidget.sync;
}
