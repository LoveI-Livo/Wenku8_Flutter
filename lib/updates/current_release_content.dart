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
const _webLogin = '新增 App 内网页登录：打开官网登录表单，登录后自动读取 Cookie，不需要手动复制。';
const _session = '修复网页登录 Cookie 被 API 未登录返回清除的问题：保留网页会话，登录一次后复用，不再反复重登。';
const _accountLoad = '修复登录后账号资料与云书架加载不出来：API 不认网页会话时自动回退官网用户页和书架读取。';
const _controls = '账号页补齐测试连接 NET/WEB、保持登录、官网会话说明、云书架与正在同步书架状态。';
const _error = '登录失败原因直接显示在登录框下方，不再只显示“登不上”。';
const _polling = '启动只自动校验一次会话，去掉反复轮询与重复登录，打开目录不会再被反复取消。';
const _keep = '0.6.8 的 20 款字体、云端备份、内置插画、真实缓存清理全部保留。';
const _changes = [
  _webLogin,
  _session,
  _accountLoad,
  _controls,
  _error,
  _polling,
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

- $_webLogin
- $_session
- $_accountLoad
- $_controls
- $_error
- $_polling
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
