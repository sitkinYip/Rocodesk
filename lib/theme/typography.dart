/// 版式令牌（Typography）。
///
/// 字体策略：**跟随系统**。
///   * Apple 平台自然是 SF Pro（Apple HIG 的原生观感，也免了打包字体）
///   * Android 回落 Roboto，Windows 回落 Segoe UI，Web 回落系统 UI 栈
/// 这样做的好处：体积零增加、各平台观感原生、中文由系统字体接管（苹方 / 思源）。
///
/// 字号阶梯取自 Apple HIG 的 Dynamic Type 常见档位，收敛成 9 档，
/// 不允许在页面里随手写 fontSize。
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

@immutable
class AppType {
  const AppType._();

  /// 系统字体栈。Flutter 的 `fontFamily: null` 就是"用平台默认"，这正是我们要的。
  static const String? system = null;

  /// 等宽：只用于**阵容码**这类需要逐字符核对的文本。
  /// 用平台等宽字体，避免打包。
  static const List<String> monoFallback = [
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];

  // ---- 字号阶梯（逻辑像素）----
  static const double sLargeTitle = 34;
  static const double sTitle1 = 28;
  static const double sTitle2 = 22;
  static const double sTitle3 = 20;
  static const double sHeadline = 17;
  static const double sBody = 17;
  static const double sCallout = 16;
  static const double sSubhead = 15;
  static const double sFootnote = 13;
  static const double sCaption = 12;
  static const double sCaption2 = 11;
  /// 中文正文行高要比拉丁文宽松一点，1.5 在读长段落时更舒服。
  static const double leadingBody = 1.5;
  static const double leadingTight = 1.25;

  /// 生成 TextTheme。`displayColor` 统一走语义色，暗黑模式自动生效。
  static TextTheme textTheme(AppColors c) {
    TextStyle s(double size, FontWeight w, {double? height, double? spacing}) =>
        TextStyle(
          fontFamily: system,
          fontSize: size,
          fontWeight: w,
          height: height,
          letterSpacing: spacing,
          color: c.textPrimary,
        );

    return TextTheme(
      displaySmall: s(sLargeTitle, FontWeight.w700, height: 1.15, spacing: -0.4),
      headlineMedium: s(sTitle1, FontWeight.w700, height: 1.2, spacing: -0.3),
      headlineSmall: s(sTitle2, FontWeight.w600, height: 1.25, spacing: -0.2),
      titleLarge: s(sTitle3, FontWeight.w600, height: 1.3),
      titleMedium: s(sHeadline, FontWeight.w600, height: 1.35),
      titleSmall: s(sSubhead, FontWeight.w600, height: 1.35),
      bodyLarge: s(sBody, FontWeight.w400, height: leadingBody),
      bodyMedium: s(sCallout, FontWeight.w400, height: leadingBody),
      bodySmall: s(sFootnote, FontWeight.w400, height: 1.45),
      labelLarge: s(sSubhead, FontWeight.w600, height: 1.2),
      labelMedium: s(sFootnote, FontWeight.w500, height: 1.2),
      labelSmall: s(sCaption, FontWeight.w500, height: 1.2, spacing: 0.2),
    );
  }

  /// 次要文字（不改变字号，只换色）。
  static TextStyle secondary(BuildContext context) =>
      context.texts.bodyMedium!.copyWith(color: context.colors.textSecondary);

  static TextStyle tertiary(BuildContext context) =>
      context.texts.bodySmall!.copyWith(color: context.colors.textTertiary);

  /// 阵容码展示：等宽 + 略小 + 可换行。
  static TextStyle code(BuildContext context) => TextStyle(
        fontFamilyFallback: monoFallback,
        fontSize: sFootnote,
        height: 1.6,
        letterSpacing: 0.4,
        color: context.colors.textPrimary,
      );
}
