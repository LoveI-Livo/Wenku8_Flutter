# 构建与签名

本文对应改版 `0.6.0+3000`。

## 1. 环境要求

| 目标 | 需要 |
|------|------|
| Android APK | Flutter SDK（Dart ≥ 3.11）、Android SDK（compileSdk 见 `android/app/build.gradle.kts`）、JDK 17 |
| iOS IPA | macOS + Xcode + 自己的 Apple 开发者证书与描述文件 |
| HarmonyOS | DevEco Studio（见 `ohos/` 与 `scripts/build_harmony.sh`） |

检查环境：

```bash
flutter --version
flutter doctor -v
java -version      # 需要 17
```

## 2. 拉取与依赖

```bash
git clone https://github.com/LoveI-Livo/Wenku8_Flutter.git
cd Wenku8_Flutter
flutter pub get
```

> `third_party/liquid_glass_easy` 是随仓库一起提供的本地依赖，`pub get` 会自动拉起，不需要单独处理。

## 3. 构建 Android

```bash
# 调试包（最快，用于自测）
flutter build apk --debug

# 发布包（需要签名配置，见下）
flutter build apk --release

# 按 ABI 拆包，体积更小
flutter build apk --release --split-per-abi
```

产物位置：

```
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## 4. 用自己的 keystore 签名

1. 生成 keystore：

```bash
keytool -genkey -v -keystore ~/wenku8-mod.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias wenku8
```

2. 新建 `android/key.properties`（**不要提交到仓库**）：

```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=wenku8
storeFile=/绝对路径/wenku8-mod.jks
```

3. 在 `android/app/build.gradle.kts` 的 `android { }` 中配置 `signingConfigs` 并让 `buildTypes.release` 使用它
   （若原工程已配置，直接用 `key.properties` 即可）。

4. 重新 `flutter build apk --release`。

> 仓库自动构建出来的是 **debug 签名**，能装能用，但不适合长期分发：
> 换签名会导致覆盖安装失败（签名不一致），正式分发请固定一个 keystore。

## 5. iOS

```bash
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist
```

需要：

- Apple 开发者账号、`ios/Runner.xcworkspace` 中的 Team 与 Bundle ID 改成你自己的；
- `ExportOptions.plist` 里的 `method`（app-store / ad-hoc / development）与描述文件匹配；
- 没有证书时可以 `flutter build ios --no-codesign` 产出未签名的 `.app`，但无法直接安装。

## 6. GitHub Actions 自动构建

`.github/workflows/android-build.yml`：

- **push 到 master / 手动触发** → 编译 release APK，作为 Artifacts 上传（保留 30 天）；
- **推送 `v*` tag** → 编译并自动创建 GitHub Release，附上 APK。

手动触发：仓库 → Actions → Build Android APK → Run workflow。

## 7. 常见问题

| 现象 | 处理 |
|------|------|
| `Dart SDK version is ... but ... requires ^3.11.3` | 升级 Flutter：`flutter upgrade` |
| `Execution failed for task ':app:...'` 且提示 SDK 版本 | 安装对应 Android SDK Platform / Build-Tools |
| `Gradle task assembleRelease failed with exit code 1` | 看完整日志，多半是 JDK 版本或签名配置 |
| `MissingPluginException` 运行时 | `flutter clean && flutter pub get` 后重装 |
| 构建卡在 `Running Gradle task 'assembleRelease'` | 首次构建要下载 Gradle 与依赖，耐心等待或配置国内镜像 |

## 8. 版本号

三处保持一致，改版本时一起改：

- `pubspec.yaml` 的 `version: 0.6.0+3000`
- `lib/updates/app_updates.dart` 的 `currentAppVersion` / `currentAppBuild`
- `lib/mod_edition.dart` 的 `modEditionVersion` / `modEditionBuild`（仅用于展示）
