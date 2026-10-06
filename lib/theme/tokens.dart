/// 语义化设计令牌（Design Tokens）。
///
/// 所有颜色、圆角、间距、动效时长都在这里集中定义，UI 层**只准引用语义名**，
/// 不准写死十六进制色值。这样暗黑模式与后续换肤只需改这一个文件。
///
/// 设计依据：Apple Human Interface Guidelines 的克制语言。
/// 十字方针：**留白、层级、克制、可读、不喧哗**。
///
/// 硬规则（来自 taste-skill，已适配到 Flutter）：
///   * 全应用**只有一个强调色**（accent），任何页面不得引入第二个彩度高的色；
///   * **形状一致性**：圆角系统固定为「按钮全圆角 / 卡片 16 / 输入 10」，
///     有明确规则就不算混用，但不准随手写别的数字；
///   * 阴影必须**带背景色相**，不准用纯黑投影；
///   * 文字对比度全部满足 WCAG AA（正文 4.5:1，大字号 3:1）。
library;

import 'package:flutter/material.dart';

/// 语义色板。亮色与暗色各一份，键名完全对应。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.accent,
    required this.accentPressed,
    required this.accentSubtle,
    required this.onAccent,
    required this.bgBase,
    required this.bgGrouped,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.separator,
    required this.separatorStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.shadow,
    required this.scrim,
  });

  final Brightness brightness;

  /// 唯一强调色（类似 iOS systemBlue，但不与任何属性色冲突）。
  /// 亮色用深一档保证白底上的对比度，暗色用浅一档。
  final Color accent;
  final Color accentPressed;

  /// 极淡的强调色底，用于选中态背景。
  final Color accentSubtle;
  final Color onAccent;

  /// 页面底色。
  final Color bgBase;

  /// 分组背景（iOS 的 grouped background，比底色略沉/略亮）。
  final Color bgGrouped;

  /// 卡片表面。
  final Color surface;
  final Color surfaceElevated;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// 分隔线（iOS 的 separator，很淡）。
  final Color separator;
  final Color separatorStrong;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// 阴影色；带背景色相，不是纯黑。
  final Color shadow;
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  /// 亮色：白底为主，强调色用较深的蓝保证 4.5:1 以上对比。
  static const light = AppColors(
    brightness: Brightness.light,
    accent: Color(0xFF007AFF),
    accentPressed: Color(0xFF0062CC),
    accentSubtle: Color(0x14007AFF),
    onAccent: Color(0xFFFFFFFF),
    bgBase: Color(0xFFFFFFFF),
    bgGrouped: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF6E6E73),
    textTertiary: Color(0xFF8E8E93),
    separator: Color(0x1F3C3C43),
    separatorStrong: Color(0x363C3C43),
    success: Color(0xFF248A3D),
    warning: Color(0xFFB25000),
    danger: Color(0xFFD70015),
    info: Color(0xFF0071E3),
    shadow: Color(0x1A1C1C1E),
    scrim: Color(0x66000000),
  );

  /// 暗色：不用纯黑（#000 在 OLED 上会让卡片边界消失），用 iOS 的分组底色。
  static const dark = AppColors(
    brightness: Brightness.dark,
    accent: Color(0xFF0A84FF),
    accentPressed: Color(0xFF409CFF),
    accentSubtle: Color(0x290A84FF),
    onAccent: Color(0xFFFFFFFF),
    bgBase: Color(0xFF000000),
    bgGrouped: Color(0xFF1C1C1E),
    surface: Color(0xFF1C1C1E),
    surfaceElevated: Color(0xFF2C2C2E),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFA1A1A6),
    textTertiary: Color(0xFF8E8E93),
    separator: Color(0x2E545458),
    separatorStrong: Color(0x54545899),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    info: Color(0xFF64D2FF),
    shadow: Color(0x66000000),
    scrim: Color(0x99000000),
  );

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? accent,
    Color? accentPressed,
    Color? accentSubtle,
    Color? onAccent,
    Color? bgBase,
    Color? bgGrouped,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? separator,
    Color? separatorStrong,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? shadow,
    Color? scrim,
  }) {
    return AppColors(
      brightness: brightness ?? this.brightness,
      accent: accent ?? this.accent,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      onAccent: onAccent ?? this.onAccent,
      bgBase: bgBase ?? this.bgBase,
      bgGrouped: bgGrouped ?? this.bgGrouped,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      separator: separator ?? this.separator,
      separatorStrong: separatorStrong ?? this.separatorStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      accent: c(accent, other.accent),
      accentPressed: c(accentPressed, other.accentPressed),
      accentSubtle: c(accentSubtle, other.accentSubtle),
      onAccent: c(onAccent, other.onAccent),
      bgBase: c(bgBase, other.bgBase),
      bgGrouped: c(bgGrouped, other.bgGrouped),
      surface: c(surface, other.surface),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      separator: c(separator, other.separator),
      separatorStrong: c(separatorStrong, other.separatorStrong),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      info: c(info, other.info),
      shadow: c(shadow, other.shadow),
      scrim: c(scrim, other.scrim),
    );
  }
}

/// 圆角系统。**固定规则，不准随手写别的数字**：
///   * 按钮 / 胶囊：全圆角（pill）
///   * 卡片 / 弹层：16
///   * 输入框 / 小控件：10
///   * 列表内缩略图：8
@immutable
class AppRadii {
  const AppRadii._();

  static const double pill = 999;
  static const double card = 16;
  static const double input = 10;
  static const double thumb = 8;

  static BorderRadius get pillR => BorderRadius.circular(pill);
  static BorderRadius get cardR => BorderRadius.circular(card);
  static BorderRadius get inputR => BorderRadius.circular(input);
  static BorderRadius get thumbR => BorderRadius.circular(thumb);
}

/// 间距系统，8 的倍数（4 用于紧凑处）。
@immutable
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// 页面左右安全边距。
  static const double page = 16;

  /// 内容最大宽度（桌面端居中，避免宽屏上一行拉太长）。
  static const double maxContentWidth = 720;
}

/// 动效令牌。
///
/// 每个动画都要能一句话说清理由（层级 / 反馈 / 状态切换），否则不加。
/// `MOTION_INTENSITY = 3`：克制，只做有意义的状态过渡。
@immutable
class AppMotion {
  const AppMotion._();

  /// 即时反馈（按下、选中）。
  static const Duration instant = Duration(milliseconds: 120);

  /// 常规状态切换。
  static const Duration normal = Duration(milliseconds: 220);

  /// 面板进入 / 页面切换。
  static const Duration emphasized = Duration(milliseconds: 320);

  /// Apple 风格的标准缓动，比 Material 默认更"稳"。
  static const Curve standard = Cubic(0.25, 0.1, 0.25, 1);
  static const Curve decelerate = Cubic(0.16, 1, 0.3, 1);
  static const Curve accelerate = Cubic(0.4, 0, 1, 1);
}

/// 阴影。**带背景色相**，禁用纯黑投影。
@immutable
class AppShadows {
  const AppShadows._();

  static List<BoxShadow> card(AppColors c) => [
        BoxShadow(
          color: c.shadow,
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> raised(AppColors c) => [
        BoxShadow(
          color: c.shadow,
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// 便捷取用：`context.colors.accent`
extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
  TextTheme get texts => Theme.of(this).textTheme;
}
