/// 构建 Material 3 主题，把 [AppColors] 注入成 ThemeExtension。
///
/// 组件层只准引用语义令牌，不准写死色值，所以这里把浮层、分隔线、
/// 输入框这些 Material 自带组件的配色也一起接管，避免出现"一处蓝一处紫"。
library;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light);
  static ThemeData dark() => _build(AppColors.dark);

  static ThemeData _build(AppColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceElevated,
      outline: c.separatorStrong,
      outlineVariant: c.separator,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bgGrouped,
      canvasColor: c.bgGrouped,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      // 关闭 Material 默认的水波纹大范围高亮，Apple 风格用轻微按压反馈即可
      highlightColor: Colors.transparent,
      splashColor: c.accentSubtle,
    );

    return base.copyWith(
      textTheme: AppType.textTheme(c),
      extensions: <ThemeExtension<dynamic>>[c],

      appBarTheme: AppBarTheme(
        backgroundColor: c.bgBase,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppType.textTheme(c).titleMedium,
        // Apple 风格的导航栏比 Material 矮一点
        toolbarHeight: 48,
      ),

      dividerTheme: DividerThemeData(
        color: c.separator,
        thickness: 1,
        space: 1,
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardR),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.separator,
          disabledForegroundColor: c.textTertiary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.pillR),
          textStyle: AppType.textTheme(c).labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: BorderSide(color: c.separatorStrong),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.pillR),
          textStyle: AppType.textTheme(c).labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.pillR),
          textStyle: AppType.textTheme(c).labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: c.textTertiary, fontSize: AppType.sBody),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: AppType.sSubhead),
        helperStyle: TextStyle(color: c.textSecondary, fontSize: AppType.sCaption),
        errorStyle: TextStyle(color: c.danger, fontSize: AppType.sCaption),
        border: OutlineInputBorder(
          borderRadius: AppRadii.inputR,
          borderSide: BorderSide(color: c.separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputR,
          borderSide: BorderSide(color: c.separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputR,
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputR,
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputR,
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.bgBase,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSubtle,
        elevation: 0,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: AppType.sCaption,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? c.accent
                : c.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? c.accent
                : c.textSecondary,
          ),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.bgBase,
        indicatorColor: c.accentSubtle,
        selectedIconTheme: IconThemeData(color: c.accent, size: 24),
        unselectedIconTheme: IconThemeData(color: c.textSecondary, size: 24),
        selectedLabelTextStyle: TextStyle(
          fontSize: AppType.sCaption,
          fontWeight: FontWeight.w600,
          color: c.accent,
        ),
        unselectedLabelTextStyle:
            TextStyle(fontSize: AppType.sCaption, color: c.textSecondary),
        labelType: NavigationRailLabelType.all,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: c.accent,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.accent,
        dividerColor: c.separator,
        labelStyle: AppType.textTheme(c).labelLarge,
        unselectedLabelStyle: AppType.textTheme(c).labelLarge,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: c.surface,
        textColor: c.textPrimary,
        iconColor: c.textSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardR),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : c.separatorStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? c.accent : c.textTertiary,
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.accentSubtle,
        side: BorderSide(color: c.separator),
        labelStyle: AppType.textTheme(c).labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.pillR),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bgBase,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardR),
        titleTextStyle: AppType.textTheme(c).titleMedium,
        contentTextStyle: AppType.textTheme(c).bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.isDark ? c.surfaceElevated : c.textPrimary,
        contentTextStyle: TextStyle(color: c.bgBase, fontSize: AppType.sSubhead),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.inputR),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.separator,
        circularTrackColor: c.separator,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.isDark ? c.surfaceElevated : c.textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: c.bgBase, fontSize: AppType.sCaption),
      ),
    );
  }
}
