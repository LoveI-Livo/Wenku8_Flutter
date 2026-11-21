# 构建与签名

对应改版 `0.6.0+3000`。

> **先读这个**：上游公开快照缺 13 个模块、120 个编译错误（清单见
> [MODIFICATIONS.md](MODIFICATIONS.md)），**原样无法构建**。本文写给两种情况：
> ① 你拿到了完整源码，想构建带本改版功能的包；② 你想知道构建时到底会卡在哪。
> 只想装个能用的 App → 直接去
> [上游 Releases](https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest)。

## 1. 环境要求

| 目标 | 需要 |
|------|------|
| Android APK | Flutter SDK（Dart ≥ 3.11）、Android SDK、JDK 17、**Gradle ≥ 9.3.1** |
| iOS IPA | macOS + Xcode + 自己的开发者证书与描述文件 |
| HarmonyOS | DevEco Studio（见 `ohos/` 与 `scripts/build_harmony.sh`） |

```bash
flutter --version     # 实测 CI 用的是 stable 3.50.1 / Dart 3.11.x
java -version         # 需要 17
```

## 2. 拉取与依赖

```bash
git clone https://github.com/LoveI-Livo/Wenku8_Flutter.git
cd Wenku8_Flutter
flutter pub get          # 这一步在公开快照上是可以成功的
```

## 3. 构建 Android

```bash
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

### 3.1 已知的第一个拦路虎：Gradle 版本

实测报错（Flutter 3.50.1）：

```
Your project's Gradle version (8.14.0) is lower than Flutter's minimum
supported version of 9.3.1. Please upgrade your Gradle version.
```

修法：改 `android/gradle/wrapper/gradle-wrapper.properties`

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.3.1-all.zip
```

然后确认 `android/settings.gradle.kts` 里的 AGP 版本支持 Gradle 9.x（AGP 8.13+ / 9.x）。

### 3.2 第二个拦路虎：Dart 编译

```bash
flutter analyze --no-pub | grep ' error • '
```

在当前公开快照上会看到 120 个错误、13 个缺失模块。**必须先把这些模块补齐**，
否则 `flutter build` 一定失败。补齐后 `flutter analyze` 无 error 再继续。

## 4. 用自己的 keystore 签名

自动构建出来的是 **debug 签名**，能装能用，但不适合长期分发（换签名会导致覆盖安装失败）。

```bash
keytool -genkey -v -keystore ~/wenku8-mod.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias wenku8
```

`android/key.properties`（**不要提交**）：

```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=wenku8
storeFile=/绝对路径/wenku8-mod.jks
```

在 `android/app/build.gradle.kts` 的 `android {}` 里配置 `signingConfigs`，
并让 `buildTypes.release` 使用它，然后重新 `flutter build apk --release`。

## 5. 拆包（体积更小）

```bash
flutter build apk --release --split-per-abi
# app-arm64-v8a-release.apk / app-armeabi-v7a-release.apk / app-x86_64-release.apk
```

## 6. 需要时再加回自动构建

本仓库**没有**挂自动构建工作流（公开快照必然构建失败，避免刷失败记录）。
等缺失模块补齐、本地 `flutter build apk` 成功后，在
`.github/workflows/android-build.yml` 放入下面内容，然后到
Actions → Build Android APK → Run workflow 手动跑：

```yaml
name: Build Android APK
on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: '可选：填 tag 就创建 Release 并上传 APK'
        required: false
permissions:
  contents: write
jobs:
  apk:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: flutter build apk --release
      - run: |
          mkdir -p dist
          cp build/app/outputs/flutter-apk/app-release.apk dist/wenku8-mod.apk
      - uses: actions/upload-artifact@v4
        with: { name: wenku8-mod-apk, path: 'dist/*.apk' }
      - if: inputs.release_tag != ''
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ inputs.release_tag }}
          files: dist/*.apk
```

> 关键点：`on` 只保留 `workflow_dispatch`，不要加 `push`。
> 否则每次推代码都会跑构建，失败记录会刷满 Actions。

## 7. iOS

```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

需要把 `ios/Runner.xcworkspace` 里的 Team、Bundle ID 换成自己的，
并准备匹配的描述文件；没有证书时 `flutter build ios --no-codesign` 只能产出未签名 `.app`。

## 8. 常见问题

| 现象 | 处理 |
|------|------|
| `Dart SDK version ... requires ^3.11.3` | `flutter upgrade` |
| `Gradle version ... lower than ... 9.3.1` | 按 3.1 改 wrapper |
| `Target of URI doesn't exist: 'xxx.dart'` | 缺模块，见 MODIFICATIONS.md 第二节 |
| `MissingPluginException` 运行时 | `flutter clean && flutter pub get` 重装 |
| 卡在 `Running Gradle task` | 首次要下 Gradle 与依赖，耐心等或配镜像 |

## 9. 版本号

三处一起改：

- `pubspec.yaml`：`version: 0.6.0+3000`
- `lib/updates/app_updates.dart`：`currentAppVersion` / `currentAppBuild`
- `lib/mod_edition.dart`：`modEditionVersion` / `modEditionBuild`（仅展示）
