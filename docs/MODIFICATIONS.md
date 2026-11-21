# 改版说明

- 上游：`mikufoxxx/Wenku8_Flutter`
- 改版版本：`0.6.0+3000`
- 作者：LoveI-Livo

## 0.6.0 更新内容

### 新增

- **缓存与存储中心**：设置 → 数据与存储 → 缓存与存储。查看正文、图片、临时文件占用，按类别清理或一键清理，清理前二次确认；只清缓存，书架、进度、书签、本地原书保留。
- **关于页改版说明**：「我的 → 关于」展示作者、联系方式、本仓库 / 原仓库 / 更早的 Android 原版入口。
- **自动打包工作流**：手动触发构建 APK 与未签名 IPA；打 tag 自动创建 Release 并上传。

### 优化

- **阅读预取**：`_prefetchAdjacent()` 的预取半径由 1 章改为 `modPrefetchRadius`（默认 2），翻页与目录跳转命中率更高。想要更快可改 3，省流量改 1。
- **信息集中管理**：署名、联系方式、仓库地址、版本号、改动清单集中在 `lib/mod_edition.dart`。
- **版本号独立**：`0.6.0+3000`，与上游区分。

### 整理

- 补齐 `pubspec.yaml` 声明的资源目录：`assets/reading_previews`、`assets/report`
- 统一 Android 构建配置：Gradle 9.3.1 / AGP 9.0
- 新增 `docs/BUILD.md` 构建与签名说明

## 换成自己的信息

改 `lib/mod_edition.dart` 顶部常量，关于页与缓存页自动同步：

```dart
const modAuthorName = 'LoveI-Livo';
const modContactEmail = '';            // 留空则不显示
const modContactQq = '';
const modContactTelegram = '';
const modContactWeChat = '';
const modContactSite = 'https://github.com/LoveI-Livo';
const modRepository = 'https://github.com/LoveI-Livo/Wenku8_Flutter';
const modOriginalRepository = 'https://github.com/mikufoxxx/Wenku8_Flutter';
const modEditionChanges = <ModChange>[ ... ];
```

## 扩展指引

### 新增网盘

`lib/cloud_sources.dart` 采用「枚举 + 客户端工厂」：

1. `CloudSourceKind` 增加枚举值
2. `CloudSourceConfig.validate()` 增加校验
3. 实现 `CloudBookClient`（`list()` / `download()`）并在工厂注册
4. `lib/cloud_library_page.dart` 表单补充字段

参考实现：`WebDavBookClient`、`QuarkBookClient`、`S3BookClient`（`lib/cloud_s3.dart`）。

### 新增书源

需要书源模型（搜索 / 详情 / 目录 / 正文）、抓取与编码识别，并与
`NovelRepository`（`lib/catalog.dart`）对接后挂到发现页；仓库已具备
`html`、`csslib`、`archive` 等依赖。
