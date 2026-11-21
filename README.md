# 轻小说文库 · 改版（Wenku8 Flutter · Mod Edition）

一个基于 [mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter) 的 **Flutter 轻小说阅读器改版**：
保留原项目的阅读器、书架、听书、统计、备份等能力，补齐了公开源码快照缺失的模块，
并加入缓存管理、阅读预取加速、改版信息与自动打包。

> 本项目是**第三方阅读客户端**，与原网站无关，不提供、不托管任何小说内容。
> 书籍请自行合法导入，或使用你有权访问的来源。

- 改版作者：**LoveI-Livo**
- 本仓库：<https://github.com/LoveI-Livo/Wenku8_Flutter>
- 原仓库（本项目来源）：<https://github.com/mikufoxxx/Wenku8_Flutter>
- 更早的 Android 原版：<https://github.com/MewX/light-novel-library_Wenku8_Android>
- 许可证：**GPL-2.0**（与原项目一致，详见 [LICENSE](LICENSE)）

---

## 一、怎么拿到安装包

### 方式 1：GitHub Actions 自动构建（推荐）

推到 `master` 或手动触发 **Actions → Build Android APK**：

1. 打开仓库的 **Actions** 页 → 左侧 **Build Android APK** → 右侧 **Run workflow**；
2. 跑完后在该次运行的 **Artifacts** 里下载 `wenku8-mod-apk`（内含调试签名的 APK）；
3. 想要正式发布：打一个 tag（例如 `git tag v0.6.0 && git push origin v0.6.0`），
   工作流会自动创建 **Release** 并把 APK 挂上去，读者可直接下载。

> 说明：仓库里构建出来的是**调试签名** APK，可以直接安装使用；
> 如果要上架或长期分发，请用你自己的 keystore 重新签名（见 [docs/BUILD.md](docs/BUILD.md)）。

### 方式 2：本地构建

需要 Flutter SDK（Dart ≥ 3.11）、Android SDK、JDK 17：

```bash
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

iOS 只能在 macOS 上构建，且需要自己的证书与描述文件：

```bash
flutter build ipa --release
```

更细的步骤（签名、常见报错、产物位置）见 **[docs/BUILD.md](docs/BUILD.md)**。

---

## 二、本改版做了什么

| # | 改动 | 说明 |
|---|------|------|
| 1 | **补齐缺失模块，工程可编译** | 原公开仓库是「部分实现的参考快照」，缺 `lan_reading_sync`、`lan_handoff_widgets`、`lan_reading_page`、`local_book_batch_page`、`listening/custom_tts*` 等文件，`flutter build` 必然失败。本改版按原调用点补回同一套接口，使工程能完整编译出安装包。 |
| 2 | **缓存与存储中心** | 设置 → 数据与存储 → **缓存与存储**：显示正文缓存 / 图片内存 / 临时文件的实时占用，支持分类清理与一键全清，清理前二次确认；不影响书架、进度、书签与本地原书。 |
| 3 | **阅读预取加速** | 相邻章节预取从前后各 1 章扩大到前后各 2 章（`lib/mod_edition.dart` 的 `modPrefetchRadius`），翻页、目录跳转时正文命中率更高，长篇小说连续阅读更顺。 |
| 4 | **改版信息与联系方式** | 「我的 → 关于」新增 **改版说明** 区块：改版作者、联系方式、本仓库地址、原仓库地址、逐条改动说明。相关常量集中在 `lib/mod_edition.dart`，改一处即可全站生效。 |
| 5 | **版本号独立** | 版本 `0.6.0`、构建号 `3000`，高于上游 `0.5.x`，避免应用内更新提示把改版覆盖成原版。 |
| 6 | **安装包自动化** | 新增 `.github/workflows/android-build.yml`：push / 手动触发即编译 APK，打 tag 自动发 Release。 |
| 7 | **文档重写** | 本 README、[docs/MODIFICATIONS.md](docs/MODIFICATIONS.md)（逐条改动与二次定制）、[docs/BUILD.md](docs/BUILD.md)（构建与签名）。 |

### 关于「多书源 / 多网盘 / 在线直读 / Web」

这些需求我逐条核对了源码，实际情况如下，写在文档里避免误解：

- **书源**：原项目把在线书源实现在**未公开的模块**里，公开快照中的 `lib/online_component.dart` 只是占位
  （提示「此源码构建未包含在线组件」），`release_notices.dart` 也明确写了「不再支持其他源或自定义书源」。
  因此公开快照**本身就不含书源引擎**，不是开关问题，需要在完整工程里补一整套抓取/解析层。
  本改版保留原有接口与占位提示，不伪造书源。
- **网盘**：源码里已支持 **WebDAV / OpenList**、**夸克网盘**、**S3 兼容对象存储** 三类，见 `lib/cloud_sources.dart`。
  新增一类网盘（蓝奏云、迅雷、123 云盘等）需要各自的登录 / 签名 / 直链接口，属于新增适配器，
  当前改版**未包含**，需要时可按 `CloudBookClient` 工厂模式扩展（结构清晰，见文件内注释）。
- **在线直读（不落盘）**：现有链路是「云端列举 → 下载到本地 → 阅读」，正文缓存按章存储
  （`lib/offline_cache.dart`）。改成「边读边取」需要改动阅读器的内容加载与缓存淘汰策略，
  属于较大范围重构，本改版未做，仅通过预取加速改善「加载慢」的体感。
- **Web 端**：应用大量使用 `dart:io`、`path_provider`、原生 MethodChannel，
  要跑在浏览器里需要把这些依赖改成条件导入，不是加个 `web/` 目录就能用。本改版未做。

> 结论：能确定交付的是 **可编译的完整工程 + APK 自动构建 + 缓存管理 + 预取加速 + 改版信息**；
> 书源与网盘扩展需要完整上游模块或按适配器自行扩展。文档不打包票，代码可查。

---

## 三、功能一览（原项目已有）

- 书架 / 收藏、阅读进度与历史、书签与摘录、笔记
- 本地书籍导入（TXT / EPUB 等）、编码识别、分卷与目录
- 阅读器：翻页与滚动、竖排、行距字体、背景、插图、词典查词
- 听书：系统 TTS / 在线语音、语速与音色
- 阅读统计、阅读报告、桌面小组件
- 备份与恢复（本机 / 云端）、S3 同步
- 多语言界面（中文 / English）

## 四、目录结构（主要部分）

```
lib/
├── main.dart                 应用入口与依赖装配
├── pages.dart                主要页面（书架 / 发现 / 详情 / 阅读器 / 设置）
├── mod_edition.dart          ★ 改版信息：署名、联系方式、版本、预取半径
├── cache_center_page.dart    ★ 缓存与存储中心
├── lan_reading_sync.dart     ★ 补回的局域网续读接口（未启用网络）
├── lan_handoff_widgets.dart  ★ 补回的续读提醒层
├── lan_reading_page.dart     ★ 局域网续读说明页
├── local_book_batch_page.dart★ 批量整理入口
├── cloud_sources.dart        网盘源抽象（WebDAV / 夸克 / S3）
├── offline_cache.dart        正文 / 插图缓存与清理
├── library_state.dart        设置、阅读进度、书架状态
└── updates/                  版本检查与「关于」页
.github/workflows/
└── android-build.yml         ★ APK 自动构建与 Release
docs/
├── BUILD.md                  ★ 构建与签名
└── MODIFICATIONS.md          ★ 改版明细与二次定制
```

## 五、常见问题

**Q：安装后提示版本更新，会不会被覆盖成原版？**
A：改版版本号 `0.6.0` 高于上游 `0.5.x`，正常不会被提示更新。若上游发布更高版本，请忽略提示或到本仓库下载。

**Q：局域网续读 / 批量整理 点了没反应？**
A：这两个模块在上游属于未公开部分，本改版补的是接口占位，页面会明确说明未启用，不会闪退。

**Q：数据会不会被清理掉？**
A：清理只针对缓存（正文、插图、图片内存、临时文件），书架、进度、书签、本地原书都保留。

**Q：能商用 / 二次分发吗？**
A：遵循 GPL-2.0：可以，但需保留许可证与版权声明，并公开修改后的源码。

## 六、致谢

- [mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter)：本项目的直接来源
- [MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android)：更早的 Android 实现
- 以及所有第三方组件、字体作者（见应用内「开源许可」页）

## 七、联系

- 作者：**LoveI-Livo**
- 主页：<https://github.com/LoveI-Livo>
- 问题反馈：请在本仓库开 [Issue](https://github.com/LoveI-Livo/Wenku8_Flutter/issues)

联系方式想换成自己的：改 `lib/mod_edition.dart` 顶部的 `modAuthorName`、`modContact*` 常量即可，
留空则对应条目自动隐藏。
