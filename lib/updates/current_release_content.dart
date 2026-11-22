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
const _lanzou = '蓝奏云改为账号登录：点账号打开官网，登录后自动保存 Cookie，直接浏览账号全部文件夹，不再要求粘贴浏览链接或直链。';
const _quark = '夸克网盘同样改为点账号官网扫码/验证码登录，自动识别登录态，不再手动粘贴 Cookie。';
const _search = '原有搜索框和搜索按钮现在会同时搜索本地书库与已登录网盘账号的全部目录，结果统一显示来源，不需要另开一套搜索界面。';
const _browse = '网盘目录按账号文件树浏览，支持进入子文件夹、全盘递归搜索、勾选导入与在线阅读。';
const _icons =
    '网盘文件补齐电子书、PDF、TXT、ZIP 和文件夹图标，标题、扩展名与大小分开显示；书架封面继续使用本地渐变封面，不依赖远程图源。';
const _api =
    '保留 0.6.10 的登录接口修复：POST 带 Content-Length、接口版本 1.30/1.13 回退、长密码与登录前测试连接/保持登录/云书架入口。';
const _links = '保留 0.6.10 的关联导入修复：iOS 符号链接与授权失效回退副本，Android 关联文件转工作副本。';
const _changes = [_lanzou, _quark, _search, _browse, _icons, _api, _links];

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

- $_lanzou
- $_quark
- $_search
- $_browse
- $_icons
- $_api
- $_links

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
