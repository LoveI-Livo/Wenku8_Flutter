import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/updates/app_updates.dart';
import 'package:wenku8_flutter/updates/current_release_content.dart';
import 'package:wenku8_flutter/updates/mod_release_history.dart';

Map<String, dynamic> releaseJson({
  String version = '0.7.7',
  String assetName = 'qingxiaoshuo-wenku-0.7.7-android.apk',
}) => {
  'tag_name': 'v$version',
  'body': '更新说明',
  'draft': false,
  'prerelease': false,
  'assets': [
    {
      'name': assetName,
      'browser_download_url':
          'https://github.com/LoveI-Livo/qingxiaoshuo-wenku/releases/download/v$version/$assetName',
      'size': 100,
      'id': 1,
    },
  ],
};

void main() {
  test('实际发布包名能被识别并选为 Android 安装包', () {
    final release = AppRelease.fromGithub(
      releaseJson(),
      'LoveI-Livo/qingxiaoshuo-wenku',
    );
    expect(release, isNotNull);
    expect(release!.assets, hasLength(1));
    expect(release.assetFor(['arm64-v8a'])?.name, contains('-android.apk'));
  });

  test('旧的 ABI 包名仍然兼容', () {
    final release = AppRelease.fromGithub(
      releaseJson(version: '0.7.5', assetName: 'wenku8-0.7.5-arm64-v8a.apk'),
      'LoveI-Livo/qingxiaoshuo-wenku',
    );
    expect(release, isNotNull);
    expect(release!.assetFor(['arm64-v8a'])?.name, contains('arm64-v8a'));
  });

  test('旧版检查器兼容的 universal 包名能被选中', () {
    final release = AppRelease.fromGithub(
      releaseJson(version: '0.7.7', assetName: 'wenku8-0.7.7-universal.apk'),
      'LoveI-Livo/qingxiaoshuo-wenku',
    );
    expect(release, isNotNull);
    expect(release!.assetFor(['arm64-v8a'])?.name, contains('universal'));
  });

  test('低版本能检测到高版本，同版本不重复提示', () {
    final release = AppRelease.fromGithub(
      releaseJson(),
      'LoveI-Livo/qingxiaoshuo-wenku',
    )!;
    expect(
      release.isNewerThan(
        const InstalledApp(version: '0.7.6', build: 3018, abis: ['arm64-v8a']),
      ),
      isTrue,
    );
    expect(
      release.isNewerThan(
        const InstalledApp(version: '0.7.7', build: 3019, abis: ['arm64-v8a']),
      ),
      isFalse,
    );
  });

  test('0.9.4 更新弹窗和历史记录都指向最新版本', () {
    expect(currentAppVersion, '0.9.4');
    expect(currentAppBuild, 3036);
    expect(modReleaseHistory.first.version, '0.9.4');
    expect(
      modReleaseHistory.map((release) => release.version),
      containsAll(['0.9.4', '0.9.3', '0.9.2']),
    );
    expect(currentReleaseSummary.join(), contains('多角色'));
    expect(currentReleaseSummary.join(), contains('悬浮耳机'));
  });

  test('非本仓库下载地址不会进入安装包列表', () {
    final json = releaseJson();
    (json['assets'] as List).first['browser_download_url'] =
        'https://example.com/qingxiaoshuo-wenku-0.7.7-android.apk';
    expect(
      AppRelease.fromGithub(json, 'LoveI-Livo/qingxiaoshuo-wenku')?.assets,
      isEmpty,
    );
  });
}
