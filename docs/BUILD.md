# 构建与签名

## 环境

| 目标 | 需要 |
|------|------|
| Android | Flutter stable（Dart ≥ 3.11）、Android SDK、JDK 17、Gradle 9.3.1+ |
| iOS | macOS + Xcode + 开发者证书 |
| HarmonyOS | DevEco Studio |

```bash
flutter --version
flutter pub get
```

`third_party/liquid_glass_easy` 是随仓库提供的本地依赖，`pub get` 会自动处理。

## Android

```bash
flutter build apk --release
flutter build apk --release --split-per-abi   # 按 ABI 拆包
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

签名：

```bash
keytool -genkey -v -keystore ~/wenku8.jks -keyalg RSA -keysize 2048 -validity 10000 -alias wenku8
```

`android/key.properties`（不要提交）：

```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=wenku8
storeFile=/绝对路径/wenku8.jks
```

在 `android/app/build.gradle.kts` 中让 `buildTypes.release` 使用该 `signingConfig` 后重新构建。

## iOS

```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

未签名包：

```bash
flutter build ios --release --no-codesign
mkdir -p Payload && cp -R build/ios/iphoneos/Runner.app Payload/
zip -qry app-unsigned.ipa Payload
```

## 自动构建

仓库 → Actions → **Build packages (manual)** → Run workflow：

- 直接运行：产出 APK 与未签名 IPA 两个 artifact
- 填入 tag（如 `v0.6.0`）：自动创建 Release 并上传安装包

## 常见问题

| 现象 | 处理 |
|------|------|
| Dart SDK 版本不匹配 | `flutter upgrade` |
| Gradle 版本偏低 | 升级到 9.3.1+ |
| `MissingPluginException` | `flutter clean && flutter pub get` |
| 首次构建慢 | 正在下载 Gradle 与依赖 |

## 版本号

三处保持一致：`pubspec.yaml`、`lib/updates/app_updates.dart`、`lib/mod_edition.dart`。
