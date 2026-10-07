/// 语义色的**可读性契约**。
///
/// ## 这里钉的是一个真实事故
///
/// `SemanticChip` 的实现是「文字与底色同一个颜色」：
///
///     background = color.withValues(alpha: 0.14)   // 同色的 14% 淡底
///     Text(color: color)                           // 文字也是同色
///
/// 文字和底色同源，所以原色越亮、对比度越低。实测压暗前：
/// **18 个属性里 16 个不达标**，最差 2.03:1（电 / 光 / 冰），
/// 要求是 WCAG AA 小字 4.5:1。
///
/// 而且这个错误**用肉眼看不出来** —— 淡彩色底上的同色字"看着挺和谐"，
/// 只是读起来费劲。所以必须靠算。
///
/// 顺带修的另一个问题：兜底色原本与「普通」完全相同，新属性掉进兜底后
/// 看起来就像普通系，用户分不出"没登记"和"真的是普通"。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/theme/type_colors.dart';

/// WCAG 相对亮度。
double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 把 14% 淡底叠在卡片白底上，得到芯片的实际背景色。
Color _chipBackground(Color color) => Color.alphaBlend(
      color.withValues(alpha: 0.14),
      const Color(0xFFFFFFFF),
    );

void main() {
  group('属性标签：文字 vs 自己的淡底', () {
    test('18 个属性全部 ≥ 4.5:1（WCAG AA 小字）', () {
      final bad = <String>[];
      TypeColors.map.forEach((name, color) {
        final r = _ratio(color, _chipBackground(color));
        if (r < 4.5) bad.add('$name ${r.toStringAsFixed(2)}:1');
      });
      expect(bad, isEmpty,
          reason: '这些属性标签读不清（要求 4.5:1）：\n  ${bad.join('\n  ')}\n'
              '修法：跑 tools/solve_type_text_colors.py 求解新值，'
              '不要凭观感调亮');
    });

    test('18 个属性都有专属色（没有掉进兜底）', () {
      expect(TypeColors.map.length, 18);
      for (final name in const [
        '普通', '火', '水', '草', '电', '冰', '武', '毒', '地',
        '翼', '萌', '虫', '幻', '幽', '恶', '龙', '机械', '光',
      ]) {
        expect(TypeColors.map.containsKey(name), isTrue, reason: '缺 $name');
      }
    });
  });

  group('特殊血脉标签：同样约束', () {
    test('6 条特殊血脉全部 ≥ 4.5:1', () {
      final bad = <String>[];
      BloodlineColors.special.forEach((name, color) {
        final r = _ratio(color, _chipBackground(color));
        if (r < 4.5) bad.add('$name ${r.toStringAsFixed(2)}:1');
      });
      expect(bad, isEmpty, reason: '读不清：\n  ${bad.join('\n  ')}');
    });

    test('6 条特殊血脉都真的特殊（不与属性重名）', () {
      expect(BloodlineColors.special.length, 6);
      for (final name in BloodlineColors.special.keys) {
        expect(TypeColors.map.containsKey(name), isFalse,
            reason: '$name 与属性同名，不该出现在 special 里');
      }
    });
  });

  group('兜底：新属性要有可读且可分辨的降级表现', () {
    test('未登记属性拿到 unknown，而不是 null / 透明 / 抛错', () {
      expect(TypeColors.of('星'), TypeColors.unknown);
      expect(TypeColors.of(''), TypeColors.unknown);
      expect(TypeColors.of('不存在的系别'), TypeColors.unknown);
    });

    test('兜底色自己是可读的（≥ 4.5:1）', () {
      final r = _ratio(TypeColors.unknown, _chipBackground(TypeColors.unknown));
      expect(r, greaterThanOrEqualTo(4.5),
          reason: '兜底也要读得清，实测 ${r.toStringAsFixed(2)}:1');
    });

    test('**兜底色与「普通」明显不同** —— 否则分不出"没登记"和"普通"', () {
      expect(TypeColors.unknown, isNot(TypeColors.map['普通']),
          reason: '两者相同时，新属性看起来就像普通系');
      // 不只是"不相等"，亮度也要有可感知的差
      final d = (_lum(TypeColors.unknown) - _lum(TypeColors.map['普通']!)).abs();
      expect(d, greaterThan(0.01),
          reason: '亮度差太小（$d），肉眼分辨不出');
    });

    test('血脉色对空值也兜底，不返回透明', () {
      final c = BloodlineColors.of('');
      expect(c.a, 1.0, reason: '不能返回半透明色，否则底色会透出来');
      expect(c, TypeColors.unknown);
    });
  });

  group('暗色模式：textOf 要提亮到可读', () {
    test('18 个属性在暗色下都 ≥ 4.5:1（对暗色卡片）', () {
      final bad = <String>[];
      for (final entry in TypeColors.map.entries) {
        final c = TypeColors.textOf(entry.key, Brightness.dark);
        // 暗色下标签底是「提亮后的色 @14%」叠在暗色卡片上
        final bg = Color.alphaBlend(
            c.withValues(alpha: 0.14), const Color(0xFF1C1C1E));
        final r = _ratio(c, bg);
        if (r < 4.5) bad.add('${entry.key} ${r.toStringAsFixed(2)}:1');
      }
      expect(bad, isEmpty, reason: '暗色下读不清：\n  ${bad.join('\n  ')}');
    });
  });
}
