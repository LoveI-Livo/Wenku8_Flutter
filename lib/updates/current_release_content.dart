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
const releaseMaintenanceNotice = '项目继续以稳定维护为主；账号、登录与阅读链路的明确问题仍会修复。';
const _apiBody =
    '修复登录时接口请求被服务器直接断开：所有接口 POST 现在都带 Content-Length，登录、账号资料和云书架不会再报 Connection closed before full header。';
const _appver = 'App 接口版本对齐原版 1.30，并保留 1.13 兼容回退，避免版本不一致导致认证失败。';
const _longPassword = '登录密码输入不再截断到 30 位，长密码可以完整提交。';
const _alwaysTools = '未登录也能看到“测试连接 NET/WEB”“保持登录”和“云书架”入口，不再等功能出现。';
const _iosLink =
    '修复 iOS「关联到 App」手动导入：文件提供方返回的符号链接不再被拒绝；无法长期授权时自动保留可读副本，关联书籍不会变成死引用。';
const _androidLink =
    '修复 Android「关联到 App」导入 PDF、MOBI、ZIP 等需要路径解析的格式：补齐关联文件转工作副本，和复制模式一样可以正常导入。';
const _quarkLogin =
    '夸克网盘支持在 App 内打开官网扫码或验证码登录，识别到 __puus 后自动保存 Cookie，不再要求手动粘贴。';
const _keep = '0.6.9 的网页登录、会话保留、字体、云端备份、内置插画、缓存清理全部保留。';
const _changes = [
  _apiBody,
  _appver,
  _longPassword,
  _alwaysTools,
  _iosLink,
  _androidLink,
  _quarkLogin,
  _keep,
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

- $_apiBody
- $_appver
- $_longPassword
- $_alwaysTools
- $_iosLink
- $_androidLink
- $_quarkLogin
- $_keep

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
