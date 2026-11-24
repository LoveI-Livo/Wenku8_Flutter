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
const _sourceSearchFix = '修复书源搜索：RSS/Atom 条目的简介现在会参与匹配和展示，搜索书名、作者、简介都能命中。';
const _searchPage =
    '搜索结果固定每页 50 条；加载成功时继续下滑自动加载下一页，加载失败时停止自动请求并显示“加载下一页”按钮；不再在 40 条处提前截断。';
const _sourceMulti =
    '小说书源支持一行填多个地址，最多 10000 个；支持 RSS、Atom、JSON Feed、JSON 列表和普通网页目录。';
const _sourceFiles =
    '书源管理支持批量导入 TXT、CSV、Legado 书源 JSON、OPML 和 HTML 书源文件，可一次导入多个文件；导入后逐个检测有效或失效，一键删除失效书源。';
const _sourceFilter = '搜索时可以指定固定来源：书源搜索可选某一个书源，网盘搜索可选某一个已连接网盘，不必每次全量搜索。';
const _linkFix =
    '修复“关联到 App”：部分文件管理器只给一次性读取权限时不再直接报错；新增独立关联入口，无法长期授权时自动保存副本，原文件仍保留。';
const _sourceWeb = '网页书源自动识别书名、作者、简介、章节目录和正文；RSS 条目链接到网页时也能在线阅读。';
const _sourceEntryFix = '修复书源条目被误判为非书导致书源搜索为空：书源条目现在不再依赖文件名扩展名。';
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
    '主搜索框拆成“文库搜索 / 网盘搜索 / 书源搜索”三个来源，支持书名、作者、标签、ID；网盘搜索覆盖所有已连接网盘，书源搜索覆盖 RSS、Atom、JSON 和网页书源。';
const _versionFold =
    '关于页版本记录改为三层折叠：大版本 → 次版本 → 单个补丁版本，每层单独展开收起；同一层同时只展开一组，当前版本带“当前”标记。';
const _sourceLimit =
    '小说书源上限提高到 10000 个，导入自动去重，列表懒加载；书源管理支持从剪贴板导入、复制全部书源、单条检测和启用/停用。';
const _updateCheck =
    '修复低版本检测不到更高版本：更新检查现在兼容实际发布包名 `qingxiaoshuo-wenku-版本-android.apk`，并按版本号选择最新 APK；同版本不会重复提示。';
const _parseProbe = '云端主机解析新增“测试接口”，不拉取书籍即可验证地址、token、PHP 和 JSON 返回。';
const _sourcePicker = '书源或网盘超过 40 个时，搜索来源改为可搜索的独立列表页，按名称或地址快速筛选。';
const _shelfIsolation =
    '普通书架与网络书架彻底隔离：普通书架只保留轻小说文库书，网盘书和书源书只出现在「网络」书架；普通书架不再显示“在线”来源标签。';
const _cloudCoverEdit =
    '网盘书详情页可更换或删除封面；封面直接上传到可道云「个人空间/云端封面」，App 只保存远端图片地址，不写本机数据。';
const _localAvatar = '「我的」页头像不再依赖登录：未登录也能从相册更换或恢复默认头像，头像保存在 App 支持目录，清理缓存不会丢。';
const _downloadCenter = '新增下载中心：集中查看已下载小说，可保存到系统文件夹；支持不限速、1/2/5/10 MB/s 下载限速。';
const _dockCustom = '底栏显示可自定义：设置页可单独隐藏发现、书架、本地、网络，「我的」作为设置入口始终保留。';
const _cloud400Fix =
    '修复 123 云盘目录提示“文件或目录不存在”、迅雷云盘提示“HTTP 400”：改用新 API 域名并允许读取 400/401/403 响应体，接口错误原样展示。';
const _cloudSearchStrip = '修复网盘搜索无结果和来源横条被压扁：搜索结果加入已在书架/已识别网盘书兜底，来源按钮恢复可点高度。';
const _sourceFold =
    '小说书源大包按文件自动折叠分组：导入“小爱”等包含数千条书源的文件只显示一个分组卡片，点开用虚拟列表展开；分组和单条都保留检测、启用/停用、删除。';
const _sourceUnlimited =
    '书源文件上传取消 16 MiB 限制，Android/iOS 系统选择器都放开到系统上限；同名同地址但规则不同的 Legado 书源不再被误去重。';
const _legado =
    '适配「阅读 / Legado」书源规则：保留 searchUrl、ruleSearch、ruleBookInfo、ruleToc、ruleContent，支持 HTML/JSON 规则、@ 链式、class/id/tag 简写、!序号、##正则和 JSON path；搜索、目录、正文可走原规则。';
const _cacheFix =
    '修复打开在线书缓存暴涨：正文插图只保留运行期内存，不再整本写盘；旧版插图缓存首次启动自动清理，最多保留 48 MiB 内存。';
const _accountFix = '账号加载失败不再只显示“登录失败”：错误原因直接展示，可重新加载；登录失败不会静默清空已有状态。';
const _onlineLabel = '网盘书的“在线读取”不再和来源信息挤在同一行，详情页只保留独立阅读入口。';

const _cloudCoverKodbox =
    '网盘封面彻底不再占本机空间：图片由解析主机直接写入可道云「个人空间/云端封面」，App 只保存远端 URL；旧版 data URI 封面首次启动自动迁移，迁移失败就清空，不会重新落盘。';
const _legadoEngine =
    '阅读/Legado 书源引擎补齐真实请求：searchUrl 逗号后的 POST/Header JSON 配置生效，目录 nextTocUrl 可翻页，正文 nextContentUrl 连续抓取，& 规则合并；支持 HTML/JSON 规则、@ 链式、class/id/tag 简写、!位置和 ##正则，搜索、详情、目录、正文都走书源原规则。';
const _normalCover =
    '普通文库书封面保持原链路：清空本地数据或图片缓存后，仍按文库图片源正常请求，不依赖网盘封面，也不写入可道云；只有网盘书封面走云端。';

const _currentChanges = [
  '书源搜索结果补回封面：Legado 的 ruleSearch.coverUrl、RSS/Atom、JSON 和网页列表图片都会带进结果；封面请求补上书源 Cookie、Authorization 和 Referer，不再因为 403 只剩渐变占位。',
  '已配置云端解析主机时，网盘搜索结果会懒加载 EPUB/TXT 内嵌封面；没配置解析主机不会为了封面下载整本书。',
  '修复书源正文只取第一段：正文规则命中多个段落节点时按顺序合并，章节内容不再只显示开头一小段。',
  '详情、目录和正文请求增加超时；解析主机超时自动回退直接读取文件，坏源或失效 CDN 不会一直转圈。',
  '云端解析只返回部分正文时仍保留全部章节标题，不再因为某一章为空就删掉整章；EPUB 正文写在 div 里也能读全。',
  '封面缓存增加 URL 指纹和失败退避，换封面或换来源后立即刷新，不反复请求失效地址。',
  '继续保留 0.8.5 的书源相对地址、搜索加速、登录凭据保险箱和网络书架分类修复。',
];

const _changes = [
  _cloudCoverKodbox,
  _legadoEngine,
  _normalCover,

  _shelfIsolation,
  _cloudCoverEdit,
  _localAvatar,
  _downloadCenter,
  _dockCustom,
  _cloud400Fix,
  _cloudSearchStrip,
  _sourceFold,
  _sourceUnlimited,
  _legado,
  _cacheFix,
  _accountFix,
  _onlineLabel,

  _versionFold,
  _sourceLimit,
  _updateCheck,
  _parseProbe,
  _sourcePicker,
  _searchPage,
  _sourceMulti,
  _sourceFiles,
  _sourceFilter,
  _linkFix,
  _sourceWeb,
  _sourceEntryFix,
  _sourceSearchFix,
  _shelfFix,
  _cloudSearchFix,
  _cloudBatch,
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

- 书源搜索结果补回封面：Legado 的 `ruleSearch.coverUrl`、RSS/Atom、JSON 和网页列表图片都会带进结果；封面请求补上书源 Cookie、Authorization 和 Referer。
- 已配置云端解析主机时，网盘搜索结果会懒加载 EPUB/TXT 内嵌封面；没配置解析主机不会为了封面下载整本书。
- 修复书源正文只取第一段：正文规则命中多个段落节点时按顺序合并，章节不再只显示开头。
- 详情、目录和正文请求增加超时；解析主机超时自动回退直接读取，坏源或失效 CDN 不会一直转圈。
- 云端解析只返回部分正文时仍保留全部章节标题；EPUB 正文写在 div 里也能读全。
- 封面缓存增加 URL 指纹和失败退避，换封面或换来源后立即刷新。

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
  ..._currentChanges,
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
    ..._currentChanges,
    releaseMaintenanceNotice,
    _androidInstall,
    _iosInstall,
    _harmonyInstall,
    _legacyInstall,
    _backup,
  ]),
];
