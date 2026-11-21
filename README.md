# 轻小说文库 · 改版

基于 [mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter) 的二次开发版本。

## 致敬

本项目完全建立在以下开源项目之上，感谢作者与所有贡献者：

- **[mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter)** —— 本项目的直接来源，阅读器、书架、听书、统计等功能均由该项目实现
- **[MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android)** —— 更早的 Android 版本，本项目间接继承其设计与数据格式
- 所有第三方组件、字体与资源的作者（见应用内「开源许可」页）

本改版仅做功能补充与项目信息整理，原作者版权与贡献全部保留。

## 下载安装

- **Android**：[v0.6.4 APK](https://github.com/LoveI-Livo/qingxiaoshuo-wenku/releases/download/v0.6.2/wenku8-mod-0.6.4-android.apk)（通用包，含 arm64-v8a / armeabi-v7a / x86_64）
- **iOS**：[v0.6.4 未签名 IPA](https://github.com/LoveI-Livo/qingxiaoshuo-wenku/releases/download/v0.6.2/wenku8-mod-0.6.4-ios-unsigned.ipa)（需 TrollStore 或自签工具安装）

所有版本与安装包见 [Releases](https://github.com/LoveI-Livo/qingxiaoshuo-wenku/releases)。

## 更新内容

### 0.6.4

**新增**

- App 全局搜索现在会同时搜索已保存的网盘 / RSS 书源，结果可直接加入书单
- 网盘浏览页支持搜索整个网盘目录，递归查书名
- 加入书单时可选「想读 / 在读 / 已读」三个书单
- 私有书源支持 Cookie 与 Basic 用户名密码，登录后可读取私有 RSS / 网页
- 网盘书阅读进度、阅读历史与本地书一致保留

### 0.6.3

**新增**

- 网盘书「加入书单 · 在线读」：书架只存直链与元数据，打开时在内存解析 TXT / EPUB / HTML，不下载原文件
- 其他书源：RSS / Atom 订阅入口，订阅条目可直接加入书单在线阅读
- 网盘书进入现有本地书架，支持分类、排序与阅读进度

### 0.6.2

**新增**

- 多网盘来源：蓝奏云普通版、蓝奏云优享版、迅雷云盘、阿里云盘、百度网盘、123 云盘、UC 网盘、其他 HTTPS 直链，均可单独配置
- 书单与分类：书架侧可按书单归类、新建 / 重命名 / 删除书单，按作者归档
- Android 文件夹扫描：支持「所有文件」授权与 SAF 目录授权，递归扫描、格式过滤、按 token 导入，不再调用即报错

**说明**

- 网盘统一使用网页复制的文件下载直链，流式读取，不保存账号 Cookie，不长期保留本地副本
- GitHub 仓库地址不允许中文字符，中文显示名放在 README 标题与仓库描述中；地址为 `qingxiaoshuo-wenku`

### 0.6.1

**修复**

- Android 构建链升级为 Gradle 9.3.1 + AGP 9.1.1，修复 `getDefaultConfig()` 与 Flutter 3.50 最低版本校验
- 补齐公开源码缺失的 `BookArchiveImport` / `BookMarkupImport` / `BookPdfImport` 占位类，APK 可正常编译启动
- iOS 恢复并修复原生占位模块，未签名 IPA 构建通过

### 0.6.0

**新增**

- 缓存与存储中心：设置 → 数据与存储 → 缓存与存储，可查看正文、图片、临时文件的占用，按类别清理或一键清理，清理前二次确认，书架与阅读记录不受影响
- 关于页新增「改版说明」区块：作者、联系方式、本仓库与原仓库入口
- 自动打包工作流：手动触发构建 APK 与未签名 IPA，打 tag 时自动创建 Release

**优化**

- 阅读预取：相邻章节预取由前后各 1 章增加至 2 章（`modPrefetchRadius` 可调），翻页与目录跳转更顺
- 项目信息集中到 `lib/mod_edition.dart`，署名、联系方式、仓库地址改一处即可全站生效
- 版本号独立为 `0.6.0+3000`，与上游区分，便于追踪来源

**整理**

- 补齐 `pubspec.yaml` 中声明的资源目录（`assets/reading_previews`、`assets/report`）
- 统一 Android 构建配置（Gradle 9.3.1 / AGP 9.1.1）
- 补充构建说明与改版文档：见 [docs/BUILD.md](docs/BUILD.md)、[docs/MODIFICATIONS.md](docs/MODIFICATIONS.md)

## 联系

- 作者：LoveI-Livo
- 主页：<https://github.com/LoveI-Livo>
- 反馈：<https://github.com/LoveI-Livo/qingxiaoshuo-wenku/issues>

## 许可

遵循 GPL-2.0，详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
