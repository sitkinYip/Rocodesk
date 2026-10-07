// 预览导出的助手描述文本（改格式后肉眼确认一下）
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/pipeline.dart';
import 'package:rocodesk/core/teamcodec.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final tables = CodecTables.fromMaps(
    pets: _read('assets/data/pets.json'),
    skills: _read('assets/data/skills.json'),
    natures: _read('assets/data/natures.json'),
    codec: _read('assets/data/codec.json'),
    variantTypes: _read('assets/data/variant_types.json'),
    learnsets: _read('assets/data/learnsets.json'),
  );
  final codec = TeamCodec(tables);

  // 用实机验证过的那张阵容图的数据
  final rt = normalizeVlmOutput({
    'magic': '进化之力',
    'team_name': '队伍3',
    'pets': [
      {
        'name': '雪影娃娃',
        'nature': '固执',
        'evs': ['物攻', '物防', '生命'],
        'skills': ['暴风雪', '冰墙', '冬至', '超级糖果'],
        'bloodline': '首领',
        'bloodline_letter': 'T',
      },
      {
        'name': '月牙雪熊',
        'nature': '固执',
        'evs': ['物攻', '物防', '生命'],
        'skills': ['双星', '先发制人', '冰点', '冰墙'],
      },
      {
        'name': '尖嘴狐仙',
        'nature': '开朗',
        'evs': ['物防', '生命', '速度'],
        'skills': ['焚烧烙印', '冬至', '火焰护盾', '炎枪'],
      },
      {
        'name': '卡瓦重（雪山附近的样子）',
        'nature': '慎重',
        'evs': ['物攻', '生命', '速度'],
        'skills': ['筛管奔流', '冬至', '晒太阳', '跺地'],
      },
      {
        'name': '饮雪狂兽',
        'nature': '慎重',
        'evs': ['物攻', '生命', '速度'],
        'skills': ['力量增效', '雪原狩猎', '冷凝', '跺地'],
      },
      {
        'name': '寂灭骨龙',
        'nature': '开朗',
        'evs': ['物攻', '生命', '魔防'],
        'skills': ['借用', '隼鳞', '电弧', '报复'],
        'bloodline': '龙',
        'bloodline_letter': 'I',
      },
    ],
  }, codec: codec, tables: tables);

  final team = toCodecTeam(rt, const {}, tables: tables);
  print('========== 给官方 AI 助手的描述 ==========');
  print(codec.toGameText(team));
  print('==========================================');
  print('');
  print('阵容码长度: ${codec.encode(team).length} 字符（不出现在上面的文本里）');
  print('队伍名「${team.name}」也不出现在文本里');
  print('血统计: ${team.pets.where((p) => p.bloodlineLetter != 'A').length} 只有血脉');
}
