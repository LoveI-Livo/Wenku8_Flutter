/// 自定义语音（Custom TTS）的占位模块。
///
/// 原工程的这部分实现在未公开模块中，公开快照只保留了 `import 'listening/custom_tts.dart';`
/// 而没有对应文件，导致工程无法编译。本改版补回同名占位文件，
/// 让 import 可以解析；如果以后拿到完整实现，直接覆盖本文件即可。
///
/// 当前没有定义任何被引用的符号，因此不影响既有听书流程
/// （系统 TTS 与在线语音分别在 `system_tts_page.dart`、`edge_tts.dart` 中实现）。
library;
