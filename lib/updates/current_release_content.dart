import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，请勿购买所谓付费版、激活码或解锁服务。**';
const releaseProjectNotice =
    '本项目为第三方客户端，并非轻小说文库（Wenku8）官方应用，也不运营该站点。在线书目与内容来自轻小说文库，本地书籍由用户自行导入，安装包不附带小说文件。';
const releaseRightsNotice =
    '小说、封面和插图归各自权利人所有。请仅使用有权访问的内容，遵守来源网站规则，不得绕过访问限制、破解 DRM，或未经许可传播、出售内容。';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const releaseMaintenanceNotice = '项目以稳定维护为主，后续非必要不再发版。';
const _fonts = '新增 6 款可下载中文字体：霞鹜新晰黑、霞鹜新致宋、霞鹜晰黑、霞鹜致宋、975 圆体、975 黑体，共 20 款。';
const _widgets = '小组件设置新增「添加到系统桌面」：Android 请求系统固定组件，iOS 按系统限制提示长按桌面添加。';
const _cloud = '备份与恢复新增云端备份：可选 WebDAV 或 S3，也可随机选一个已连接网盘上传备份 JSON。';
const _images = '阅读纪念新增 4 张内置插画：秋叶书签、黄昏列车、晨山云海、春雨窗边，全部打包进安装包。';
const _cache = '缓存与存储继续按真实目录统计并真正清理：正文插图、网页与应用缓存、临时文件、小组件图片与图片内存。';
const _lan = '局域网续读改为手动开启；开启时弹出系统本地网络权限，未授权不会监听。';
const _performance = '启动与运行性能不回退：云备份配置只在备份页加载，图片全部本地读取，保留延迟初始化与 debounce。';
const _changes = [
  _fonts,
  _widgets,
  _cloud,
  _images,
  _cache,
  _lan,
  _performance,
];
const _androidInstall = '**Android**：直接覆盖更新，不要先卸载旧版。';
const _iosInstall = '**iOS**：提供未签名包，主应用与小组件均需自行签名。';
const _harmonyInstall = '**HarmonyOS**：提供未签名包，需自行签名后安装。';
const _legacyInstall = '**iOS／HarmonyOS 0.5.0 用户**：请先手动更新一次。';
const _backup = '升级、整理存储或同步前，请先备份重要书籍和阅读记录。';
const publicReleaseNotes =
    '''
### 免费使用，请勿付费

$releaseFreeNotice

$releaseProjectNotice

$releaseRightsNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### 本次更新

- $_fonts
- $_widgets
- $_cloud
- $_images
- $_cache
- $_lan
- $_performance

### 后续维护

$releaseMaintenanceNotice

### 安装说明

- $_androidInstall
- $_iosInstall
- $_harmonyInstall
- $_legacyInstall

$_backup
''';
const currentReleaseNotes = publicReleaseNotes;
const currentReleaseSummary = [
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  ..._changes,
  releaseMaintenanceNotice,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    releaseFreeNotice,
    releaseProjectNotice,
    releaseRightsNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('本次更新与后续维护', [
    ..._changes,
    releaseMaintenanceNotice,
    _androidInstall,
    _iosInstall,
    _harmonyInstall,
    _legacyInstall,
    _backup,
  ]),
];
