import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/cloud_sources.dart';

class _MemoryStorage implements CloudConfigStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? data) async => value = data;
}

void main() {
  test('同一种网盘可以保存多个连接并在重启后恢复', () async {
    final storage = _MemoryStorage();
    final settings = CloudSourceSettings(storage: storage);
    await settings.load();
    await settings.save(
      CloudSourceKind.webdav,
      const CloudSourceConfig(
        kind: CloudSourceKind.webdav,
        connectionId: 'webdav-1',
        address: 'https://one.example/dav/',
        username: 'one',
        password: 'pass',
      ),
    );
    await settings.save(
      CloudSourceKind.webdav,
      const CloudSourceConfig(
        kind: CloudSourceKind.webdav,
        connectionId: 'webdav-2',
        address: 'https://two.example/dav/',
        username: 'two',
        password: 'pass',
      ),
    );
    expect(settings.configsFor(CloudSourceKind.webdav).length, 2);
    expect(
      settings[CloudSourceKind.webdav]?.address,
      'https://one.example/dav/',
    );

    final restored = CloudSourceSettings(storage: storage);
    await restored.load();
    expect(restored.configsFor(CloudSourceKind.webdav).length, 2);
    expect(
      restored
          .configsFor(CloudSourceKind.webdav)
          .map((config) => config.address),
      containsAll(<String>[
        'https://one.example/dav/',
        'https://two.example/dav/',
      ]),
    );
  });

  test('删除主连接后自动提升同类型的下一个连接', () async {
    final storage = _MemoryStorage();
    final settings = CloudSourceSettings(storage: storage);
    await settings.load();
    await settings.save(
      CloudSourceKind.webdav,
      const CloudSourceConfig(
        kind: CloudSourceKind.webdav,
        connectionId: 'webdav-1',
        address: 'https://one.example/dav/',
        username: 'one',
        password: 'pass',
      ),
    );
    await settings.save(
      CloudSourceKind.webdav,
      const CloudSourceConfig(
        kind: CloudSourceKind.webdav,
        connectionId: 'webdav-2',
        address: 'https://two.example/dav/',
        username: 'two',
        password: 'pass',
      ),
    );
    await settings.remove(settings[CloudSourceKind.webdav]!);
    expect(settings.configsFor(CloudSourceKind.webdav).length, 1);
    expect(
      settings[CloudSourceKind.webdav]?.address,
      'https://two.example/dav/',
    );
  });

  test('刷新 Cookie 不会丢掉同一条连接的其他字段', () async {
    final storage = _MemoryStorage();
    final settings = CloudSourceSettings(storage: storage);
    await settings.load();
    const original = CloudSourceConfig(
      kind: CloudSourceKind.lanzou,
      connectionId: 'lanzou-1',
      address: 'https://example.com/share',
      allowHttp: true,
      cookie: 'phpdisk_info=old',
    );
    await settings.save(CloudSourceKind.lanzou, original);
    await settings.rotate(original, 'phpdisk_info=new');
    final updated = settings[CloudSourceKind.lanzou]!;
    expect(updated.cookie, 'phpdisk_info=new');
    expect(updated.address, 'https://example.com/share');
    expect(updated.allowHttp, isTrue);
    expect(updated.connectionId, 'lanzou-1');
  });

  test('优享版官网 Cookie 能保存多个账号和稳定设备号', () async {
    final storage = _MemoryStorage();
    final settings = CloudSourceSettings(storage: storage);
    await settings.load();
    const first = CloudSourceConfig(
      kind: CloudSourceKind.lanzouPro,
      connectionId: 'lanzouPro-1',
      cookie: 'appToken=token-one; theme=light',
      deviceId: 'device-one',
    );
    const second = CloudSourceConfig(
      kind: CloudSourceKind.lanzouPro,
      connectionId: 'lanzouPro-2',
      cookie: 'appToken=token-two',
      deviceId: 'device-two',
    );
    await settings.save(CloudSourceKind.lanzouPro, first);
    await settings.save(CloudSourceKind.lanzouPro, second);
    expect(settings.configsFor(CloudSourceKind.lanzouPro).length, 2);
    expect(CloudSourceKind.lanzouPro.isWebLogin, isTrue);
    expect(CloudSourceKind.lanzouPro.isAccount, isTrue);
    expect(CloudSourceKind.lanzouPro.isDirectLink, isFalse);

    final restored = CloudSourceSettings(storage: storage);
    await restored.load();
    final configs = restored.configsFor(CloudSourceKind.lanzouPro).toList();
    expect(
      configs.map((config) => config.deviceId),
      containsAll(<String>['device-one', 'device-two']),
    );
  });
  test('优享版官网 Cookie 保存在同一连接并保留设备号', () async {
    final storage = _MemoryStorage();
    final settings = CloudSourceSettings(storage: storage);
    await settings.load();
    const original = CloudSourceConfig(
      kind: CloudSourceKind.lanzouPro,
      connectionId: 'lanzouPro-1',
      cookie: 'appToken=first-token',
      deviceId: 'device-one',
    );
    original.validate();
    await settings.save(CloudSourceKind.lanzouPro, original);
    await settings.rotate(original, 'appToken=second-token');
    final updated = settings[CloudSourceKind.lanzouPro]!;
    expect(updated.cookie, 'appToken=second-token');
    expect(updated.deviceId, 'device-one');
    expect(CloudSourceKind.lanzouPro.isWebLogin, isTrue);
    expect(CloudSourceKind.lanzouPro.isDirectLink, isFalse);
    expect(CloudSourceKind.lanzouPro.isAccount, isTrue);
  });
}
