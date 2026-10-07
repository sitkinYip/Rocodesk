/// 属性色板。
///
/// 18 个属性各自有一个**官方识别色**（冰=蓝、火=橙…），这是游戏的既有语义，
/// 不算"随意引入第二个强调色" —— 它们是**数据可视化色**，与 UI 强调色职责不同。
/// 但为守住克制原则，属性色只用在**小面积标识**（圆点、图标底、标签文字），
/// 绝不用作大面积背景。
///
/// 命名统一为单字：普通/火/水/草/电/冰/武/毒/地/翼/萌/虫/幻/幽/恶/龙/机械/光
///
/// ## ⚠️ 这是"数据更新时要手动改"的唯一一处，且必须手动
///
/// 颜色是**设计资产**，不是数据 —— 没法从数据包推导，官方也不会给。
/// 所以官方新增一个属性时，**这里要补一条**，否则新属性会掉进 [TypeColors.unknown]：
///
///   * 界面不会崩（有兜底），但会显示成中性灰而不是属性色
///   * 所以兜底色**刻意与「普通」不同**，让"没登记"看起来就是没登记
///
/// 找这一处的方法：这个文件里 18 个属性名连在一起出现，grep 属性名能找到它。
/// （`test/data_driven_test.dart` 的源码级不变量只查「名 -> 字母」映射，
///   不查颜色表 —— 因为颜色本来就该留在代码里。）
library;

import 'package:flutter/material.dart';

@immutable
class TypeColors {
  const TypeColors._();

  /// 属性 -> 颜色。
  ///
  /// ## ⚠️ 这些值是被**对比度**约束过的，不要凭观感调亮
  ///
  /// 取值参照各属性在图鉴与小程序里的识别色，但**统一压暗到「文字 vs 自己的
  /// 14% 淡底」≥ 4.5:1**（WCAG AA 小字）。原因是 [SemanticChip] 的用法：
  ///
  ///     background = color.withValues(alpha: 0.14)   // 同色淡底
  ///     Text(color: color)                           // 文字也是同色
  ///
  /// 文字和底色同源，所以原色越亮、对比度越低。压暗前的实测：
  /// **18 个属性里 16 个不达标，最差 2.03:1**（电 / 光 / 冰 最严重）。
  ///
  /// 这些值是 `tools/solve_type_text_colors.py` **算出来的** ——
  /// 保住色相与饱和度、只降明度，取"刚好达标"的那个点。
  /// 所以每个属性仍一眼可辨（红还是红、蓝还是蓝），但文字真的读得清。
  ///
  /// 改色前先跑：
  /// ```
  /// python tools/solve_type_text_colors.py     # 重新求解
  /// cd app && flutter test test/type_colors_test.dart   # 验证
  /// ```
  static const Map<String, Color> map = {
    '普通': Color(0xFF69696E),
    '火': Color(0xFFBF3416),
    '水': Color(0xFF156BB0),
    '草': Color(0xFF3B752A),
    '电': Color(0xFF856400),
    '冰': Color(0xFF287282),
    '武': Color(0xFFA84C3A),
    '毒': Color(0xFF954CA1),
    '地': Color(0xFF8A6131),
    '翼': Color(0xFF4F66AE),
    '萌': Color(0xFFBF2A60),
    '虫': Color(0xFF5B7021),
    '幻': Color(0xFF7950C9),
    '幽': Color(0xFF6B5BA8),
    '恶': Color(0xFF8A4B5C),
    '龙': Color(0xFF5660C3),
    '机械': Color(0xFF546D78),
    '光': Color(0xFF83630E),
  };

  /// 未登记属性时的兜底色。
  ///
  /// 两个约束（都实测过）：
  ///   1. **与「普通」明显不同**（`#5F5F66` vs `#69696E`）——
  ///      否则新属性看起来就像普通系，用户分不出"没登记"和"真的是普通"。
  ///   2. **过对比度**：5.22:1（原来是 #8E8E93，只有 2.84:1）。
  static const Color unknown = Color(0xFF5F5F66);

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
  ///
  /// 和 [TypeColors.map] 同一个约束：**「文字 vs 自己的 14% 淡底」≥ 4.5:1**。
  /// 这几个值同样由 `tools/solve_type_text_colors.py` 求解得出
  /// （原来的首领 #C9982F 只有 2.32:1，是全表最差的之一）。
  static const Map<String, Color> special = {
    '首领': Color(0xFF85641F),
    '巨兽': Color(0xFF826447),
    '黑魔法': Color(0xFF5B3A87),
    '异核': Color(0xFF2B746B),
    '污染': Color(0xFF636E34),
    '奇异': Color(0xFFA14691),
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
