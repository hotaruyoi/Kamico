import 'package:flutter/foundation.dart' show kReleaseMode;

import 'app_version.dart';

/// 发行渠道。beta 版由 `--dart-define=JM_CHANNEL=beta` 打进包内，和
/// Gradle 的 `-PjmChannel=beta`（改包名与桌面图标名）成对使用。
const _channel = String.fromEnvironment('JM_CHANNEL');

const _beta = _channel == 'beta';

/// 版本标签。beta 通道只改显示串，`lib/app_version.dart` 里的三段式数字
/// 仍由构建脚本按原样改写，否则脚本的版本正则会对不上。
/// 后缀与分支名、产物目录名保持一致：feature+1.0.3beta / 1.0.3beta。
const versionLabel = _beta ? '${appVersion}beta' : appVersion;

const appName = _beta
    ? (kReleaseMode ? 'kamico Beta' : 'kamico Beta Debug')
    : (kReleaseMode ? 'kamico' : 'kamico Debug');

/// beta 版单独占一个导出目录，和正式版并存时不互相覆盖。
const publicDownloadsFolder = _beta
    ? (kReleaseMode ? 'kamico-beta' : 'kamico-beta-debug')
    : (kReleaseMode ? 'kamico' : 'kamico-debug');
