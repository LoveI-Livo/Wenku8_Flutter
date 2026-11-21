# 轻小说文库 · 改版（Wenku8 Flutter · Mod Edition）

基于 [mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter) 的
**Flutter 轻小说阅读器改版源码**：加缓存管理、阅读预取加速、改版信息与联系方式替换，
并把「哪些能改、哪些改不了」写清楚。

> ⚠️ **先看这一段，避免白折腾**
>
> 上游的公开仓库是**部分实现的参考快照**（作者在 `docs/RELEASING.md` 里明确写了
> 「不能独立构建或复现正式安装包」）。实测缺 **13 个模块、120 个编译错误**，
> `flutter build apk` 必然失败。**本仓库同样不能直接编译出安装包**，这不是改版造成的。
>
> 所以：
> - 想要**能装的成品** → 去上游发版页下载：<https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest>
>   （官方 0.5.6，含 arm64 / armeabi-v7a / x86_64 三种 APK、未签名 IPA、未签名 HAP）
> - 想要**本改版的成品** → 需要先拿到完整源码，把本仓库的改动合并进去（见第五节，附文件清单）

- 改版作者：**LoveI-Livo**
- 本仓库：<https://github.com/LoveI-Livo/Wenku8_Flutter>
- 原仓库：<https://github.com/mikufoxxx/Wenku8_Flutter>
- 更早的 Android 原版：<https://github.com/MewX/light-novel-library_Wenku8_Android>
- 许可证：**GPL-2.0**（与原项目一致，见 [LICENSE](LICENSE)）

---

## 一、这个改版改了什么

| # | 改动 | 文件 | 说明 |
|---|------|------|------|
| 1 | **缓存与存储中心** | `lib/cache_center_page.dart`（新增）<br>`lib/pages.dart`（接入） | 在「设置 → 数据与存储」新增入口：实时显示正文缓存 / 图片内存 / 临时文件占用，支持分类清理与一键全清，二次确认。只调用既有接口，不碰书架、进度、书签、本地原书。 |
| 2 | **阅读预取加速** | `lib/pages.dart`<br>`lib/mod_edition.dart` | 相邻章节预取从前后各 1 章扩大到前后各 2 章（`modPrefetchRadius`，可调 1/2/3），翻页与目录跳转命中率更高。 |
| 3 | **改版信息与联系方式** | `lib/mod_edition.dart`（新增）<br>`lib/updates/update_page.dart` | 「我的 → 关于」新增「改版说明」区块：作者、联系方式、本仓库 / 原仓库 / 更早原版链接、逐条改动。信息集中在 `mod_edition.dart`，改一处全站生效。 |
| 4 | **版本号独立** | `pubspec.yaml`<br>`lib/updates/app_updates.dart` | `0.6.0+3000`，高于上游 `0.5.6`，避免应用内更新把自己覆盖回原版。 |
| 5 | **资源声明修复** | `assets/reading_previews/`（补 8 个 webp）<br>`assets/report/README.md` | `pubspec.yaml` 声明了这些资源但快照里没有，补齐后少一类构建错误。 |
| 6 | **文档** | `README.md`、`docs/BUILD.md`、`docs/MODIFICATIONS.md` | 构建步骤、签名、缺失模块清单、二次定制方法。 |

## 二、公开快照到底缺什么（实测）

`flutter analyze` 的原始结果：**13 个缺失模块、120 个错误**，涉及 17 个文件。

缺失模块（被现有代码 `import`，但仓库里没有文件）：

```
enhancement.dart                      listening/enhancement.dart
enhancement_controls.dart             listening/enhancement_controls.dart
local_book_scanner.dart
local_import_batch.dart
local_scan_page.dart
local_scan_selection.dart
portable_book_prepare.dart
reader_paper_geometry.dart
reading_report_page.dart
reading_widget_reference.dart
reading_widget_reference_capture.dart
reading_widget_skin.dart
reading_widget_skin_picker.dart
```

受影响的功能：本地扫描导入、批量导入、阅读报告页、桌面小组件皮肤、听书增强、局域网续读、
自定义语音、纸张几何（阅读器排版）。

**我不伪造这些模块。** 凭 120 个错误的调用面去猜 API，只会得到一个"看着能编译、跑起来到处报错"的工程，
对谁都没好处。所以本仓库保持诚实：改版只动能确认的部分，构建缺口如实记录。

## 三、想要能安装的版本

### 选项 A：用官方成品（立刻可用）

<https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest>

| 平台 | 文件 | 说明 |
|------|------|------|
| Android | `wenku8-0.5.6-arm64-v8a.apk` | 绝大多数手机 |
| Android | `wenku8-0.5.6-armeabi-v7a.apk` | 老旧 32 位设备 |
| Android | `wenku8-0.5.6-x86_64.apk` | 模拟器 / x86 平板 |
| iOS | `wenku8-0.5.6-ios-unsigned.ipa` | 未签名，需自签（AltStore / TrollStore 等） |
| HarmonyOS | `wenku8-0.5.6-harmony-unsigned.hap` | 未签名，需自行签名 |

### 选项 B：拿到完整源码后合并本改版

见第五节。

## 四、为什么不直接加书源 / 网盘 / Web

需求我逐条核对了源码，结论如下（不打包票、可查证）：

| 需求 | 源码现状 | 结论 |
|------|----------|------|
| 更多书源 | `lib/online_component.dart` 只有占位（抛 `OnlineComponentUnavailable`）；`release_notices.dart` 写明「不再支持其他源或自定义书源」。在线书源引擎不在公开部分。 | 不是开关问题，需要从零写抓取 + 解析 + 与 `NovelRepository` 对接。 |
| 更多网盘（蓝云、迅雷…） | 已有 WebDAV/OpenList、夸克、S3 三类，结构是 `CloudSourceKind` 枚举 + `CloudBookClient` 工厂。 | 新增一类要各自的登录/签名/直链接口，属新增适配器，本改版未做（扩展方法见 `docs/MODIFICATIONS.md`）。 |
| 在线直读不落盘 | 现状是「云端列举 → 下载 → 按章缓存在 `offline_cache.dart`」。 | 「边读边取」要改阅读器内容加载与缓存淘汰，属大范围重构，本改版只做了预取加速。 |
| Web 端 | 大量 `dart:io`、`path_provider`、原生 MethodChannel。 | 需要条件导入改造，不是加 `web/` 目录就能跑。 |

> 能确定交付的是：**可读的源码改动 + 准确的构建说明 + 缓存管理 + 预取加速 + 改版信息**。
> 书源与网盘扩展要等完整上游模块，或按适配器自行扩展。

## 五、把本改版合并到完整源码

如果拿到了完整工程（或上游作者提供的完整源码），本改版只有 6 个文件需要处理：

```bash
# 1. 完整源码里加入两个新文件
cp lib/mod_edition.dart        <完整工程>/lib/
cp lib/cache_center_page.dart  <完整工程>/lib/

# 2. 三个文件按 diff 合并（本仓库 vs 上游同名文件）
#    lib/pages.dart                    缓存入口 + 预取半径
#    lib/updates/update_page.dart      关于页「改版说明」区块
#    lib/updates/app_updates.dart      版本号
#    pubspec.yaml                      版本号

# 3. 资源（若完整工程已自带可跳过）
cp -r assets/reading_previews <完整工程>/assets/
```

然后用 `docs/BUILD.md` 的步骤构建。

## 六、怎么把信息换成你自己的

改 `lib/mod_edition.dart` 顶部常量即可，界面（关于页、缓存页）自动同步：

```dart
const modAuthorName    = 'LoveI-Livo';
const modContactEmail  = '';                             // 留空则隐藏
const modContactQq     = '';
const modContactTelegram = '';
const modContactWeChat = '';
const modContactSite   = 'https://github.com/LoveI-Livo';
const modRepository    = 'https://github.com/LoveI-Livo/Wenku8_Flutter';
const modOriginalRepository = 'https://github.com/mikufoxxx/Wenku8_Flutter';
const modEditionChanges = <ModChange>[ ... ];            // 改动清单，界面直接渲染
```

## 七、常见问题

**Q：为什么 Actions 里没有自动构建？**
A：公开快照缺 13 个模块，构建必然失败。与其反复刷一堆失败记录，不如不挂这个工作流。
需要时按 `docs/BUILD.md` 第六节的 YAML 片段加回来（手动触发）。

**Q：改了这些，能不能直接用？**
A：本仓库是**源码**。你现有的官方 APK 不会因为这里改了而变化；要得到带这些改动的安装包，
需要按第五节合并到完整源码后构建。

**Q：会不会动我的数据？**
A：缓存中心只清缓存；书架、进度、书签、本地原书都保留。

**Q：能商用 / 二分发吗？**
A：GPL-2.0：可以，但保留许可证与版权声明，并公开修改后的源码。

## 八、致谢

- [mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter)：本项目的直接来源
- [MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android)：更早的 Android 实现
- 第三方组件与字体作者（见应用内「开源许可」页）

## 九、联系

- 作者：**LoveI-Livo**
- 主页：<https://github.com/LoveI-Livo>
- 反馈：<https://github.com/LoveI-Livo/Wenku8_Flutter/issues>
