// 调试：白屏排查。逐个验证启动期会跑到的加载逻辑。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main() {
  print('1) 直接解析 bloodline_ranks.json');
  try {
    final raw = File('assets/data/bloodline_ranks.json').readAsStringSync();
    final m = jsonDecode(raw) as Map<String, dynamic>;
    print('   ✓ 顶层键: ${m.keys.toList()}');
    final ranks = m['ranks'];
    print('   ranks 类型: ${ranks.runtimeType}');
    if (ranks is Map) {
      print('   条数: ${ranks.length}');
      print('   样例: ${ranks.entries.take(2).map((e) => '${e.key} -> ${e.value}').toList()}');
    }
  } catch (e) {
    print('   ✗ $e');
  }

  print('');
  print('2) 解析 icons/index.json');
  try {
    final raw = File('assets/icons/index.json').readAsStringSync();
    final m = jsonDecode(raw) as Map<String, dynamic>;
    print('   ✓ 顶层键: ${m.keys.toList()}');
    final bl = m['bloodline'];
    final sk = m['skill'];
    print('   bloodline 类型=${bl.runtimeType} 条数=${bl is Map ? bl.length : "?"}');
    print('   skill 类型=${sk.runtimeType} 条数=${sk is Map ? sk.length : "?"}');
    if (bl is Map && bl.isNotEmpty) {
      final k = bl.keys.first;
      print('   样例: $k -> assets/icons/bloodline/$k.png');
      print('   文件存在: ${File('assets/icons/bloodline/$k.png').existsSync()}');
    }
  } catch (e) {
    print('   ✗ $e');
  }

  print('');
  print('3) 其余资产文件是否都在');
  for (final f in [
    'assets/data/pets.json',
    'assets/data/skills.json',
    'assets/data/natures.json',
    'assets/data/codec.json',
    'assets/data/variant_types.json',
    'assets/data/learnsets.json',
    'assets/data/bloodline_ranks.json',
    'assets/data/manifest.json',
  ]) {
    final file = File(f);
    final ok = file.existsSync();
    print('   ${ok ? "✓" : "✗"} $f  ${ok ? "${(file.lengthSync() / 1024).toStringAsFixed(1)} KB" : "缺失"}');
  }

  print('');
  print('4) manifest 里的 version 与文件清单');
  try {
    final m = jsonDecode(File('assets/data/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    print('   version=${m['version']}');
    final files = (m['files'] as Map).keys.toList();
    print('   清单: $files');
  } catch (e) {
    print('   ✗ $e');
  }
}
