class ModRelease {
  const ModRelease({
    required this.version,
    required this.date,
    required this.summary,
    required this.changes,
  });

  final String version;
  final String date;
  final String summary;
  final List<String> changes;
}

/// Every release published from this repository, newest first. This is what
/// the About page folds open per version; the README deliberately stays free
/// of changelog text.
const modReleaseHistory = <ModRelease>[
  ModRelease(
    version: '0.6.7',
    date: '2026-11-22',
    summary: '在线组件登录、缓存完整清理、版本记录折叠',
    changes: [
      '移除“此源码构建未包含在线组件”，接入文库账号登录、云端书架、在线书目搜索与章节正文。',
      '登录后可搜索在线书库、读取目录与正文，并与本地书架、阅读记录共用同一套数据。',
      '缓存与存储补全网页与应用缓存、桌面小组件图片、临时文件、正文插图、图片内存五类统计。',
      '每一类缓存都能单独清理；一键清理会删除全部可重建缓存，清掉的小组件图片不会立即重新写回。',
      '关于页改为按版本折叠：默认收起，点版本标题展开查看该版全部修改与修复。',
      '修复缓存页顶部被标题栏遮挡、下滑回弹，以及空书架也显示二十多 MB 的问题。',
      '启动与运行性能：小组件渲染延后到首帧后，旧缓存扫描、更新检查、局域网初始化和系列归并全部后移，减少启动和用一段时间后的卡顿。',
    ],
  ),
  ModRelease(
    version: '0.6.6',
    date: '2026-11-22',
    summary: '纪念图片、局域网续读、小组件删除',
    changes: [
      '补回阅读纪念缺失的主题预设图片，纪念方式与图片恢复完整。',
      '局域网续读改为真实 UDP 广播：同一 Wi-Fi 下发送章节与阅读位置，另一台设备收到后续读。',
      '小组件支持新建与删除；修复部分小组件图片超过 2 MB 被丢弃而不显示的问题。',
      '首次安装只生成一张默认小组件，旧版五张默认卡片收敛为一张，并清理遗留临时图片。',
      '修复缓存与存储页顶部错位、下滑回弹。',
      '移除关于页的赞助跳转链接。',
    ],
  ),
  ModRelease(
    version: '0.6.5',
    date: '2026-11-22',
    summary: '网页登录 Cookie、原版书单、安装包同页',
    changes: [
      '私有书源支持 App 内弹出网页登录，登录完成自动获取 Cookie 并回填。',
      '保持原版书单左右滚动 UI 不变，网盘书接入原书架与书单。',
      '网盘书进入 App 原有全局搜索，阅读历史、章节、书名、作者与本地书一致。',
      'Android APK 与 iOS 未签名 IPA 合回同一发布页。',
    ],
  ),
  ModRelease(
    version: '0.6.4',
    date: '2026-11-21',
    summary: '全局搜索云书、整盘搜索、三书单',
    changes: [
      'App 全局搜索同时搜索已保存的网盘与 RSS/Atom 书源，结果可直接打开或加入书单。',
      '网盘浏览页新增“搜索整个网盘”，递归查找书名。',
      '加入书单可选「想读 / 在读 / 已读」三个书单。',
      '私有书源支持 Cookie 与 Basic 用户名/密码，登录后读取私有 RSS / 网页。',
      'EPUB 读取 OPF 的 dc:title / dc:creator，HTML 读取 og:title / meta author，TXT 识别“作者：”。',
      '阅读位置按书籍 ID + 章节 ID 保存，退出重进可续读；远程书保留书名、作者与章节字段。',
    ],
  ),
  ModRelease(
    version: '0.6.3',
    date: '2026-11-21',
    summary: '网盘书在线读、RSS 书源',
    changes: [
      '网盘直链书可“加入书单 · 在线读”，书架只存书名与直链，正文在内存解析，不下载原文件。',
      '网盘书直接进入现有书架，可分类、排序、记录进度，与本地书混排。',
      '新增 RSS / Atom 书源入口，订阅条目可直接加入书单并在线阅读。',
      '保留蓝奏普通/优享、迅雷、阿里、百度、123、UC 与其他 HTTPS 直链。',
    ],
  ),
  ModRelease(
    version: '0.6.2',
    date: '2026-11-21',
    summary: '多网盘来源、书单分类、文件夹扫描',
    changes: [
      '新增蓝奏云普通版、蓝奏云优享版、迅雷、阿里、百度、123、UC 与其他 HTTPS 直链，每个来源独立配置。',
      '书单支持新建、重命名、删除，按作者归档。',
      'Android 支持“所有文件”授权与 SAF 目录授权，递归扫描、格式过滤、按 token 导入。',
      '保留缓存与存储中心、阅读预取加速。',
    ],
  ),
  ModRelease(
    version: '0.6.1',
    date: '2026-11-21',
    summary: '修复 Android / iOS 构建',
    changes: [
      '修复 Android 构建链：Gradle 9.3.1 + AGP 9.1.1，解决 getDefaultConfig() 与 Flutter 3.50 最低版本校验。',
      '补齐公开源码缺失的文档导入占位类，APK 可正常编译、安装、启动。',
      '修复 iOS 原生占位模块的 Swift 编译错误，未签名 IPA 构建通过。',
      '关于页改版说明同步为真实状态，不再声称“无法编译”。',
    ],
  ),
  ModRelease(
    version: '0.6.0',
    date: '2026-11-21',
    summary: '首个可安装改版',
    changes: [
      '产出可安装 Android APK 与 iOS 未签名 IPA。',
      '补齐公开源码缺失的文档导入占位类，应用可启动与阅读。',
      '缓存与存储中心：正文缓存、图片缓存、临时文件分类清理。',
      '阅读预取加速（前后各 2 章）。',
      '关于页标注原作者、原仓库与本改版说明。',
    ],
  ),
];
