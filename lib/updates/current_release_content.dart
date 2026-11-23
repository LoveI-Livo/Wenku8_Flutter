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
const _cloudParse =
    '云端主机解析：在「网盘在线阅读 → 云端主机解析」填写自己的 PHP 接口地址和密钥，网盘直链交给主机拉取、解析并返回书名、作者、简介、封面、章节与插图；主机未配置、失败或格式不支持时自动回退本机解析。';
const _cloudAuto = '网盘搜索每次实时读取当前全部已连接来源：新连接一个网盘后无需重启，自动进入“网盘搜索”，不再依赖固定来源列表。';
const _shelfFix =
    '修复网盘书加入书架、加入书单后书架仍显示 0 本：云端书籍 ID 改为独立区间，不再被误判成本地书而被静默拒绝；加入后书架和书单会立即出现记录。';
const _cloudSearchFix =
    '修复网盘搜索明明有文件却搜不到：除文件名、作者、书源简介外，未命中时会对体积较小的文件读取内部书名、作者、简介，再按关键词匹配；不下载原书到本机，单次检索有文件数和时间上限。';
const _sourceSearchFix =
    '修复书源搜索：RSS/Atom 条目的简介现在会参与匹配和展示，搜索书名、作者、简介都能命中。';
const _cloudBatch =
    '网盘浏览交互调整：点右侧圆圈直接加入书架，不再先勾选再回到顶部点按钮；需要加入书单或一次处理多本时，点“批量选择”勾选后统一操作。';
const _cloudDocs =
    '云端解析部署说明改为通用占位教程，只写环境要求、上传步骤、自测方法和安全事项；不包含个人主机地址、接口地址或密钥，`config.php` 已加入忽略规则。';
const _cloudShelf =
    '网盘书加入书架后与普通在线书一致：详情页齿轮或书架菜单可进入“书籍设置”，编辑书名、作者、标签、简介和分类，也可移出书架并保留阅读进度。';
const _cloudMetadata =
    '网盘书加入书架或首次打开时，从 EPUB / DOCX / ODT / FB2 / TXT / HTML 文件内识别书名、作者、简介、封面和 EPUB 正文插画；只缓存封面与插画，原文件仍留在网盘，不保存到本机。';
const _cloudCache =
    '网盘书封面与正文插图缓存单独列入「缓存与存储」，可查看占用并随时清理；正文在内存中解析，退出阅读后由系统回收，不占安装存储。';
const _threeSearch =
    '主搜索框拆成“文库搜索 / 网盘搜索 / 书源搜索”三个来源，支持书名、作者、标签、ID；网盘搜索覆盖所有已连接网盘（账号目录与直链），书源搜索检索 RSS/Atom。';
const _changes = [
  _shelfFix,
  _cloudSearchFix,
  _sourceSearchFix,
  _cloudBatch,
  _cloudDocs,
  _cloudParse,
  _cloudAuto,
  _cloudShelf,
  _cloudMetadata,
  _cloudCache,
  _threeSearch,
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

- $_shelfFix
- $_cloudSearchFix
- $_sourceSearchFix
- $_cloudBatch
- $_cloudDocs
- $_cloudParse
- $_cloudAuto
- $_cloudShelf
- $_cloudMetadata
- $_cloudCache
- $_threeSearch

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
