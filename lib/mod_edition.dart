/// 改版信息（Mod Edition）。
///
/// 这个文件只存放常量，不参与任何业务逻辑，方便二次修改：
/// 1. 想换成自己的署名和联系方式，改下面的常量即可，界面会自动同步；
/// 2. 联系方式留空字符串时，对应条目不会显示；
/// 3. 改动清单直接增删 [modEditionChanges] 里的条目。
library;

/// 改版名称，显示在「关于」页的标题里。
const modEditionName = '轻小说文库';

/// 版本号与构建号：需要和 pubspec.yaml、lib/updates/app_updates.dart 保持一致。
const modEditionVersion = '0.8.6';
const modEditionBuild = 3028;

/// 改版作者。
const modAuthorName = 'LoveI-Livo';

/// 联系方式：留空即隐藏对应条目。
const modContactEmail = '';
const modContactQq = '';
const modContactTelegram = '';
const modContactWeChat = '';
const modContactSite = 'https://github.com/LoveI-Livo';

/// 本改版仓库（你现在用的这个仓库）。
const modRepository = 'https://github.com/LoveI-Livo/qingxiaoshuo-wenku';

/// 原仓库：Flutter 移植版，本项目由它复制而来。
const modOriginalRepository = 'https://github.com/mikufoxxx/Wenku8_Flutter';

/// 更早的 Android 原版，保留致谢。
const modLegacyRepository =
    'https://github.com/MewX/light-novel-library_Wenku8_Android';

/// 阅读器相邻章节预取半径。
///
/// 原版只预取前后各 1 章；改版扩大到 2 章，翻页时更少等待，
/// 代价是略微增加内存与流量占用。想要更快可以改成 3，想省流量改回 1。
const modPrefetchRadius = 2;

/// 概况，显示在「关于」页顶部。
const modEditionSummary =
    '本仓库是原项目（mikufoxxx/Wenku8_Flutter）的改版源码，遵循 GPL-2.0 许可证。'
    '在保留原有阅读器、书架、听书、统计等设计的基础上，加入了缓存管理、阅读预取加速，'
    '并把应用内的项目信息与联系方式替换为改版作者的信息。\n\n'
    '上游公开仓库是「部分实现的参考快照」。本改版已补齐构建模块，接入文库账号与在线书目，'
    '文件夹扫描、局域网续读已可用；可以稳定产出 Android APK 与 iOS 未签名 IPA。';

/// 改版说明的条目：标题 + 说明。
class ModChange {
  const ModChange(this.title, this.detail);

  final String title;
  final String detail;
}

/// 改动清单，显示在「关于 → 改版说明」。
const modEditionChanges = <ModChange>[
  ModChange(
    '云端主机解析',
    '可把自己的 PHP 虚拟主机设为解析服务：网盘直链交给主机拉取和解析，'
        '返回书名、作者、简介、封面、章节与插图；主机失败时自动回退本机解析。',
  ),
  ModChange(
    '新增网盘自动纳入搜索',
    '每次网盘搜索都实时读取当前全部已连接来源；新连接一个网盘后无需重启，'
        '自动进入“网盘搜索”，不再依赖固定来源列表。',
  ),
  ModChange(
    '网盘书加入书架',
    '网盘书可独立“加入书架”，不下载原文件；加入后与普通在线书一致，'
        '可在书籍设置中编辑书名、作者、标签、简介和分类。',
  ),
  ModChange(
    '网盘书内嵌信息',
    '从 EPUB / DOCX / ODT / FB2 / TXT / HTML 识别书名、作者、简介、封面与 EPUB 插画；'
        '仅缓存封面和插画，原文件留在网盘。',
  ),
  ModChange(
    '搜索结果分页',
    '搜索结果固定每页 50 条；加载成功时继续下滑自动加载下一页，失败时停止自动请求'
        '并显示“加载下一页”按钮；不会在 40 条处提前截断。',
  ),
  ModChange(
    '更多小说书源',
    '书源地址支持一行多个，最多 10000 个；可批量导入 TXT、CSV、Legado JSON、OPML'
        '和 HTML 书源文件，支持剪贴板导入、单条检测、启用停用和删除失效。RSS、Atom、'
        'JSON Feed、JSON 列表和普通网页目录都能识别，网页书源会自动提取书名、作者、简介、目录和正文。',
  ),
  ModChange(
    '三类搜索',
    '主搜索框分为文库搜索、网盘搜索、书源搜索；支持书名、作者、标签和 ID，'
        '网盘搜索覆盖所有已连接网盘，书源搜索覆盖已配置的订阅和网页书源。',
  ),
  ModChange(
    '云端备份与恢复',
    '「备份与恢复」支持把本地备份 JSON 上传到已连接的 WebDAV 或 S3；'
        '点备份或恢复后弹出网盘列表手动选择，读取时恢复最近一份。备份不含账号信息。',
  ),
  ModChange(
    '中文字体扩充',
    '字体列表增加到 20 款，新增霞鹜新晰黑、霞鹜新致宋、霞鹜晰黑、霞鹜致宋、'
        '975 圆体与 975 黑体；全部固定版本、校验文件长度后才启用。',
  ),
  ModChange(
    '桌面组件入口',
    '小组件设置新增「添加到系统桌面」；Android 使用系统固定请求，'
        'iOS 按系统限制提示长按桌面添加。',
  ),
  ModChange(
    '内置阅读插画',
    '阅读纪念新增秋叶书签、黄昏列车、晨山云海、春雨窗边 4 张内置插画，'
        '图片随安装包提供，不依赖远程图源。',
  ),
  ModChange(
    '在线组件与账号登录',
    '「文库账号」不再提示源码构建缺少在线组件：账号密码登录、云端书架、在线书目搜索、'
        '目录与章节正文均通过文库公开接口读取，并与本地书架、阅读历史共用同一套数据。',
  ),
  ModChange(
    '构建与安装包修复',
    '改用 Gradle 9.3.1 + AGP 9.1.1，补齐文档转换占位类，Android APK 与 iOS 未签名 IPA '
        '均可从 GitHub Actions 稳定产出，并在 Release 提供下载。',
  ),
  ModChange(
    '新增「缓存与存储」中心',
    '实时显示正文插图、网页与应用缓存、临时文件、桌面小组件图片与图片内存占用，'
        '每一类均可单独清理，一键全清会删除所有可重建缓存；'
        '不影响书架、进度、书签、登录状态与本地原书。',
  ),
  ModChange(
    '阅读预取加速',
    '相邻章节预取从前后各 1 章扩大到前后各 2 章，翻页与目录跳转时正文命中率更高，'
        '长篇小说连续阅读更顺。数值在 lib/mod_edition.dart 的 modPrefetchRadius。',
  ),
  ModChange(
    '启动与运行性能',
    '小组件渲染、旧缓存扫描、更新检查、局域网初始化与系列归并全部移出首帧，'
        '并合并重复发布任务；启动和阅读中不再被这些后台 I/O 抢占主线程。',
  ),
  ModChange(
    '项目信息与联系方式改为改版作者',
    '「关于」页新增改版说明区块，作者、联系方式、本仓库与原仓库地址都在这里；'
        '许可页保留原项目版权声明。',
  ),
  ModChange(
    '资源声明修复',
    '补上 pubspec 声明但快照缺失的 assets/reading_previews 图片与 assets/report 目录，'
        '减少一类构建错误。',
  ),
  ModChange(
    '构建真相写进文档',
    '上游公开快照缺 13 个模块、约 120 个编译错误，无法直接构建出 APK。'
        'README 与 docs/BUILD.md 写清了缺口、排查方法与合并到完整源码的步骤。',
  ),
];

/// 说明性文字，显示在「关于 → 改版说明」末尾。
const modEditionNotice =
    '本改版仅调整客户端功能与信息展示，不运营在线书库、不托管小说文件；'
    '书籍内容请自行合法导入或使用你有权访问的来源。'
    '原项目版权归其作者与贡献者所有，改版部分同样遵循 GPL-2.0。';
