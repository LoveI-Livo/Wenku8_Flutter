# 改版明细与二次定制

- 基线：`mikufoxxx/Wenku8_Flutter` master（`ebcd7f1`，版本 `0.5.6+2277`）
- 改版版本：`0.6.0+3000`
- 原则：**只改能确认的部分；不伪造缺失模块；构建缺口如实记录**

## 一、本改版的实际改动

### 1. 新增 `lib/cache_center_page.dart`

「设置 → 数据与存储 → 缓存与存储」：

- **统计**：正文缓存（`OfflineCacheStore.bytes`）、图片内存（`imageCache.currentSizeBytes`）、
  临时目录（递归累加文件大小）；
- **清理**：正文与插图 / 图片内存 / 临时文件，分类清理 + 一键全清；
- **安全**：全部二次确认；只调用既有接口（`OfflineCacheStore.clear()`、`imageCache.clear()`、
  删除临时目录内容），不触碰书架、阅读进度、书签与本地导入的原书。

### 2. 新增 `lib/mod_edition.dart`

集中的改版信息常量：作者、联系方式、本仓库 / 原仓库 / 更早原版地址、版本号、
预取半径 `modPrefetchRadius`、改动清单 `modEditionChanges`。

改这一处，关于页与缓存页同步生效。

### 3. `lib/pages.dart`

- `_dataOptions` 新增「缓存与存储」入口（`settings-cache-center`）；
- `_prefetchAdjacent()`：预取半径由写死的 `1` 改为 `modPrefetchRadius`（默认 2），
  三处 `removeWhere(...abs() > 1)` 与预取循环同步扩大，预取窗口和淘汰窗口保持一致。

### 4. `lib/updates/update_page.dart`

「关于」页在「重要说明」之后新增「改版说明」：概况、版本行、逐条改动、
作者与联系方式（留空自动隐藏）、原仓库 / 本仓库 / 更早原版三个外链（`url_launcher`）。

### 5. 版本号

| 位置 | 值 |
|------|-----|
| `pubspec.yaml` | `0.6.0+3000` |
| `lib/updates/app_updates.dart` | `currentAppVersion='0.6.0'`、`currentAppBuild=3000` |
| `lib/mod_edition.dart` | `modEditionVersion` / `modEditionBuild`（仅展示） |

高于上游 `0.5.6`，应用内更新不会把改版覆盖回原版。

### 6. 资源声明修复

`pubspec.yaml` 声明但快照缺失的资源：

- `assets/reading_previews/*.webp`（8 个）→ 从仓库已有的 `assets/reading_art/*-117.webp` 复制补齐；
- `assets/report/`（目录）→ 放 `README.md` 占位，使目录存在。

### 7. 未做 / 已回滚

- **没有**补写局域网续读、自定义语音、批量导入等缺失模块：缺 13 个模块、120 个编译错误，
  盲写等于造假，检查过一轮后已放弃（相关占位文件未保留在最终提交里）。
- **没有**挂自动构建工作流：公开快照构建必然失败，避免刷失败记录。
- **没有**改动书源、网盘、Web 相关实现（原因见 README 第四节）。

## 二、公开快照的构建缺口（实测）

`flutter analyze`：**13 个缺失模块 / 120 个错误 / 17 个文件**。

| 缺失模块 | 主要影响 |
|----------|----------|
| `listening/enhancement.dart`、`listening/enhancement_controls.dart` | 听书增强、自定义语音设置 |
| `local_book_scanner.dart`、`local_scan_page.dart`、`local_scan_selection.dart`、`local_import_batch.dart` | 本地书扫描、批量导入 |
| `portable_book_prepare.dart` | 文档导入预处理（`book_documents.dart`） |
| `reader_paper_geometry.dart` | 阅读器纸张排版几何 |
| `reading_report_page.dart` | 阅读报告页 |
| `reading_widget_reference.dart`、`reading_widget_reference_capture.dart`、`reading_widget_skin.dart`、`reading_widget_skin_picker.dart` | 桌面小组件样式与截图 |

另有 `main.dart` 中 `CustomSpeechSettings`、`pages.dart` 中 `CustomSpeechPage` / `LanSendBookSheet`
等符号无定义，全部来自上述缺失模块。

这与上游 `docs/RELEASING.md` 的说明一致：「本仓库是部分实现的参考快照……不能独立构建」。

## 三、把改版合并到完整源码

需要处理的文件一共 6 个：

| 文件 | 处理方式 |
|------|----------|
| `lib/mod_edition.dart` | 新增，直接拷贝 |
| `lib/cache_center_page.dart` | 新增，直接拷贝 |
| `lib/pages.dart` | 合并 3 处：import、`_dataOptions` 入口、`_prefetchAdjacent` 半径 |
| `lib/updates/update_page.dart` | 合并 1 处：关于页「改版说明」区块 + 2 个 import |
| `lib/updates/app_updates.dart` | 版本号 2 行 |
| `pubspec.yaml` | 版本号 1 行 |

合并后用 `docs/BUILD.md` 的步骤构建。

### 直接取补丁

本仓库保留了上游完整提交历史，改动可以直接导出成补丁：

```bash
# 在完整工程里执行
git remote add mod https://github.com/LoveI-Livo/Wenku8_Flutter.git
git fetch mod master

# 只取改版改动（相对上游 ebcd7f1）
git diff ebcd7f1..mod/master -- lib/ pubspec.yaml > mod-edition.patch
git apply --3way mod-edition.patch

# 资源
git checkout mod/master -- assets/reading_previews assets/report
```

上游基线 commit 为 `ebcd7f1`（`Refine mobile activity layout and unavailable data states`）。

## 四、继续扩展

### 加一类网盘

`lib/cloud_sources.dart` 结构清晰：

1. `CloudSourceKind` 加枚举值（带显示名）；
2. `CloudSourceConfig.validate()` 加该类型校验分支；
3. 实现 `CloudBookClient`（`list()` + `download()`），在工厂 `switch` 注册；
4. `lib/cloud_library_page.dart` 的添加/编辑表单补字段；
5. 参考现成实现：`WebDavBookClient`、`QuarkBookClient`、`S3BookClient`（`lib/cloud_s3.dart`）。

### 加书源

公开快照没有书源引擎（`lib/online_component.dart` 是占位）。要加需要：

- 书源模型（搜索 / 详情 / 目录 / 正文四段规则）；
- 抓取与编码识别（仓库已有 `html`、`csslib`、`archive` 等依赖可用）；
- 与 `NovelRepository`（`lib/catalog.dart` 的 `Novel` / `NovelChapter`）对接，再挂到发现页。

### 调预取速度

`lib/mod_edition.dart` 的 `modPrefetchRadius`：`1` 省流量（原版行为）、`2` 默认、`3` 最顺但更吃内存。

## 五、已知限制

| 项 | 状态 |
|----|------|
| 直接构建安装包 | ✗ 缺 13 个模块（上游快照限制） |
| 局域网续读 / 批量整理 / 自定义语音 / 阅读报告 | ✗ 随缺失模块一并缺失 |
| 多书源 / 多网盘 / 在线直读 / Web | ✗ 未实现，见 README 第四节 |
| 缓存管理 / 预取加速 / 改版信息 / 版本号 | ✓ 已完成 |
