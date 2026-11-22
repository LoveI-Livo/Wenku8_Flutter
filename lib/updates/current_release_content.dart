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
const _cloudShelf =
    '网盘书新增独立的“加入书架（不下载）”：勾选后直接写入书架，不复制文件；加入后与普通在线书一致，详情页齿轮和书架菜单都能进入“书籍设置”，编辑书名、作者、标签、简介和分类，也可移出书架并保留阅读进度。';
const _cloudMetadata =
    '网盘书加入书架或首次打开时，从 EPUB / DOCX / ODT / FB2 / TXT / HTML 文件内识别书名、作者、简介、封面和 EPUB 正文插画；只缓存封面与插画，原文件仍留在网盘，不保存到本机。';
const _cloudCache =
    '网盘书封面与正文插图缓存单独列入「缓存与存储」，可查看占用并随时清理；正文在内存中解析，退出阅读后由系统回收，不占安装存储。';
const _threeSearch =
    '主搜索框拆成“文库搜索 / 网盘搜索 / 书源搜索”三个来源，支持书名、作者、标签、ID；网盘搜索覆盖所有已连接网盘（账号目录与直链），书源搜索检索 RSS/Atom，切换来源会保留当前关键词。';
const _loginFix =
    '修复网页登录误判：只有在网页里检测到文库登录 Cookie（jieqiuserinfo）才返回成功，普通站点 Cookie 不再被当成登录成功。';
const _backupPick = '云端备份不再随机选网盘：点“选择网盘并备份/恢复”后弹出已连接网盘列表，手动选择目标后执行。';
const _formats =
    '保留格式扩展：DOCX、ODT、RTF、FB2、HTML、Markdown、ZIP、MOBI、PRC、AZW、AZW3；PDF 本机与网盘均可提取正文。';
const _api =
    '保留登录接口修复：POST 带 Content-Length、接口版本 1.30/1.13 回退、长密码与登录前测试连接/保持登录/云书架入口。';
const _links = '保留关联导入修复：iOS 符号链接与授权失效回退副本，Android 关联文件转工作副本。';
const _changes = [
  _cloudShelf,
  _cloudMetadata,
  _cloudCache,
  _threeSearch,
  _loginFix,
  _backupPick,
  _formats,
  _api,
  _links,
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

- $_cloudShelf
- $_cloudMetadata
- $_cloudCache
- $_threeSearch
- $_loginFix
- $_backupPick
- $_formats
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
