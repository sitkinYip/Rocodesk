/// 属性色板。
///
/// 18 个属性各自有一个**官方识别色**（冰=蓝、火=橙…），这是游戏的既有语义，
/// 不算"随意引入第二个强调色" —— 它们是**数据可视化色**，与 UI 强调色职责不同。
/// 但为守住克制原则，属性色只用在**小面积标识**（圆点、图标底、标签文字），
/// 绝不用作大面积背景。
///
/// 命名统一为单字：普通/火/水/草/电/冰/武/毒/地/翼/萌/虫/幻/幽/恶/龙/机械/光
library;

import 'package:flutter/material.dart';

@immutable
class TypeColors {
  const TypeColors._();

  /// 属性 -> 颜色。取值参照各属性在图鉴与小程序里的识别色，
  /// 统一压低饱和度以便与 Apple 风格的克制底色共存。
  static const Map<String, Color> map = {
    '普通': Color(0xFF8E8E93),
    '火': Color(0xFFE8593A),
    '水': Color(0xFF3B9BE8),
    '草': Color(0xFF54A83C),
    '电': Color(0xFFD9A400),
    '冰': Color(0xFF4FB3C9),
    '武': Color(0xFFB5523F),
    '毒': Color(0xFF9B4FA8),
    '地': Color(0xFFA8763C),
    '翼': Color(0xFF7E8FC4),
    '萌': Color(0xFFE0729A),
    '虫': Color(0xFF7E9B2E),
    '幻': Color(0xFF8E6BD1),
    '幽': Color(0xFF6B5BA8),
    '恶': Color(0xFF8A4B5C),
    '龙': Color(0xFF5A64C4),
    '机械': Color(0xFF6E8C99),
    '光': Color(0xFFD4A017),
  };

  /// 未登记属性时的兜底色（中性灰）。
  static const Color unknown = Color(0xFF8E8E93);

  static Color of(String type) => map[type] ?? unknown;

  /// 该属性色的**淡底**，用于标签背景。透明度 0.14 保证文字仍可读。
  static Color subtleOf(String type) => of(type).withValues(alpha: 0.14);

  /// 属性标签文字色：暗色模式下把亮度提上去，保证 4.5:1 对比。
  static Color textOf(String type, Brightness b) {
    final base = of(type);
    if (b == Brightness.light) return base;
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + 0.22).clamp(0.0, 0.92))
        .withSaturation((hsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
  }
}

/// 血脉色：24 条血脉里 18 条与属性同名，沿用属性色；其余 6 条给专属色。
@immutable
class BloodlineColors {
  const BloodlineColors._();

  /// 与属性不同名的特殊血脉。
  static const Map<String, Color> special = {
    '首领': Color(0xFFC9982F),
    '巨兽': Color(0xFF8A6A4B),
    '黑魔法': Color(0xFF5B3A87),
    '异核': Color(0xFF2E7D74),
    '污染': Color(0xFF6E7A3A),
    '奇异': Color(0xFFB24FA0),
  };

  static Color of(String bloodline) {
    if (bloodline.isEmpty) return TypeColors.unknown;
    final s = special[bloodline];
    if (s != null) return s;
    return TypeColors.of(bloodline);
  }

  static Color subtleOf(String bloodline) =>
      of(bloodline).withValues(alpha: 0.14);

  static Color textOf(String bloodline, Brightness b) {
    if (bloodline.isEmpty) return TypeColors.unknown;
    if (special.containsKey(bloodline)) {
      final base = of(bloodline);
      if (b == Brightness.light) return base;
      final hsl = HSLColor.fromColor(base);
      return hsl
          .withLightness((hsl.lightness + 0.24).clamp(0.0, 0.92))
          .toColor();
    }
    return TypeColors.textOf(bloodline, b);
  }
}
