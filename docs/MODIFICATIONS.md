# 改版明细与二次定制

改版基线：`mikufoxxx/Wenku8_Flutter`（master，版本 0.5.6+2277）
改版版本：`0.6.0+3000`

## 一、为什么必须补模块

原公开仓库在 `docs/RELEASING.md` 中写明：

> 本仓库是部分实现的参考快照，保留了一些未提供模块的引用，**不能独立构建或复现正式安装包**。

实测缺失的本地模块（被 `lib/main.dart`、`lib/pages.dart` 直接 import）：

| 缺失文件 | 被谁引用 | 本改版的处理 |
|----------|----------|--------------|
| `lib/lan_reading_sync.dart` | main.dart、pages.dart | 补回接口：`LanReadingSync`、`LanSyncScope`、`LanHandoffService`、`LanHandoffReceipt`、`LanHandoffResolution`（网络功能未启用） |
| `lib/lan_handoff_widgets.dart` | main.dart、pages.dart | 补回 `LanHandoffMonitor`（无请求时直接渲染 child） |
| `lib/lan_reading_page.dart` | pages.dart | 补回说明页，点开不崩 |
| `lib/local_book_batch_page.dart` | pages.dart | 补回 `openLocalBookBatch` 与清单页 |
| `lib/listening/custom_tts.dart` | main.dart | 仅 import 未使用符号；保留同名占位文件即可编译 |
| `lib/listening/custom_tts_page.dart` | pages.dart | 同上 |

另外 `pubspec.yaml` 声明的资源在快照里也有缺口，本改版一并修正：

- `assets/reading_previews/*.webp`（8 个）→ 从仓库已有的 `assets/reading_art/*-117.webp` 复制补齐；
- `assets/report/`（目录）→ 补一个 `README.md` 占位，使目录存在。

> 补的是**接口与占位**，不是编造上游私有的网络实现。因此「局域网续读」「批量整理」两个入口
> 在界面上会明确显示「当前构建未启用」，其它功能不受影响。

## 二、逐条改动

### 1. 新增 `lib/mod_edition.dart`

集中的改版信息常量：

```dart
const modAuthorName = 'LoveI-Livo';       // 作者
const modContactEmail = '';                // 留空则不显示
const modContactQq = '';
const modContactTelegram = '';
const modContactWeChat = '';
const modContactSite = 'https://github.com/LoveI-Livo';
const modRepository = '...';               // 本仓库
const modOriginalRepository = '...';       // 原仓库
const modLegacyRepository = '...';         // 更早的 Android 原版
const modPrefetchRadius = 2;               // 预取半径
const modEditionChanges = <ModChange>[...];// 改动清单
```

**换成你自己的信息**：只改这个文件即可，关于页、缓存页会自动同步。

### 2. 新增 `lib/cache_center_page.dart`

设置 → 数据与存储 → 缓存与存储：

- 统计：正文缓存（`OfflineCacheStore.bytes`）、图片内存（`imageCache.currentSizeBytes`）、临时目录；
- 清理：分类清理（正文与插图 / 图片内存 / 临时文件）+ 一键全清；
- 安全：全部走二次确认，只调用既有的清理接口（`OfflineCacheStore.clear()`、`imageCache.clear()`），
  不碰书架、进度、书签、本地原书。

### 3. `lib/pages.dart`

- 设置页新增「缓存与存储」入口（`_dataOptions`）；
- 阅读器 `_prefetchAdjacent()`：预取半径由固定 `1` 改为 `modPrefetchRadius`（默认 2），
  预取窗口与淘汰窗口同步扩大，翻页更少等待。

### 4. `lib/updates/update_page.dart`

「关于」页在「重要说明」之后新增「改版说明」区块：概况、版本、逐条改动、
作者与联系方式、原仓库 / 本仓库 / 更早原版链接（`url_launcher` 打开外部浏览器）。

### 5. 版本号

- `pubspec.yaml`：`0.6.0+3000`
- `lib/updates/app_updates.dart`：`currentAppVersion` / `currentAppBuild`
- 效果：高于上游 `0.5.x`，应用内更新提示不会把改版覆盖回原版。

### 6. `.github/workflows/android-build.yml`

push / 手动触发编译 APK；推送 `v*` tag 自动创建 Release 并上传 APK。

## 三、想继续扩展时

### 加一类网盘

`lib/cloud_sources.dart` 是完整的适配器结构：

1. 在 `CloudSourceKind` 增加枚举值（带显示名）；
2. 在 `CloudSourceConfig.validate()` 增加该类型的校验分支；
3. 实现一个 `CloudBookClient`（`list()` + `download()`），在工厂 `switch` 里注册；
4. 在 `lib/cloud_library_page.dart` 的添加/编辑表单里补该类型的字段；
5. 参考已有实现：`WebDavBookClient`、`QuarkBookClient`、`S3BookClient`（`lib/cloud_s3.dart`）。

### 加书源

公开快照**没有**书源引擎（`lib/online_component.dart` 是占位，抛
`OnlineComponentUnavailable`）。要加书源等于补一整套：

- 书源模型（搜索 / 详情 / 目录 / 正文四段规则）；
- HTTP 抓取与编码识别（仓库已有 `archive`、`html`、`csslib`、`charset` 相关依赖可用）；
- 与 `NovelRepository` 对接（`lib/catalog.dart` 的 `Novel` / `NovelChapter`），再挂到发现页。

不建议在未拿到完整上游模块时硬改，容易与现有缓存/进度模型冲突。

### 改预取速度

`lib/mod_edition.dart` 的 `modPrefetchRadius`：

- `1`：省流量（原版行为）
- `2`：默认，翻页更顺
- `3`：最顺，但内存与流量更高

## 四、已知限制

| 功能 | 状态 |
|------|------|
| 局域网续读 | 接口已补，网络未启用（页面有说明） |
| 批量整理本地书 | 清单页可用，批量操作未启用 |
| 自定义语音（custom_tts） | 仅保留 import 占位，页面对应入口不显示 |
| 阅读报告 `assets/report/` | 目录占位，报告导出相关资源缺失 |
| 书源 / 网盘扩展 / 在线直读 / Web | 未实现，见 README 第二节说明 |
