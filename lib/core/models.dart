/// 阵容码的数据模型。
///
/// 与 Python 端 `roco/teamcode.py` 的 `Pet` / `Team` 一一对应，
/// 字段名保持可读一致，便于两端口径对照。
library;

/// 一只精灵。
class Pet {
  Pet({
    this.index = 0,
    this.petId = '',
    this.petName = '',
    this.bloodlineLetter = '',
    this.bloodline = '',
    this.natureLetter = '',
    this.nature = '',
    this.natureUp = '',
    this.natureDown = '',
    this.evCode = '',
    List<String>? evsList,
    List<String>? skills,
    List<String>? skillCodes,
    List<String>? skillSlots,
    this.tailUp = 'A',
    this.tailDown = 'A',
    List<String>? notes,
  })  : evsList = evsList ?? <String>[],
        skills = skills ?? <String>[],
        skillCodes = skillCodes ?? <String>[],
        skillSlots = skillSlots ?? <String>[],
        notes = notes ?? <String>[];

  int index;
  String petId;
  String petName;
  String bloodlineLetter;
  String bloodline;
  String natureLetter;
  String nature;
  String natureUp;
  String natureDown;
  String evCode;

  /// 三个个体资质维度（汉字），如 `['物攻','物防','生命']`。
  List<String> evsList;
  List<String> skills;
  List<String> skillCodes;

  /// 四个技能槽（空槽为 `''`），保留原始槽位顺序。
  List<String> skillSlots;
  String tailUp;
  String tailDown;
  List<String> notes;

  /// 人类可读的三围串，例如 `物攻 物防 生命`。
  String get evs => evsList.join(' ');

  Map<String, dynamic> toJson() => {
        'index': index,
        'petId': petId,
        'petName': petName,
        'bloodlineLetter': bloodlineLetter,
        'bloodline': bloodline,
        'natureLetter': natureLetter,
        'nature': nature,
        'natureUp': natureUp,
        'natureDown': natureDown,
        'evCode': evCode,
        'evsList': evsList,
        'skills': skills,
        'skillCodes': skillCodes,
        'skillSlots': skillSlots,
        'tailUp': tailUp,
        'tailDown': tailDown,
      };
}

/// 一支队伍（最多 6 只）。
class Team {
  Team({
    this.name = '',
    this.magicCode = '',
    this.magic = '',
    List<Pet>? pets,
    this.header = '',
    this.countLetter = '',
    this.tailMarker = 'F',
    this.payload = '',
    List<String>? notes,
  })  : pets = pets ?? <Pet>[],
        notes = notes ?? <String>[];

  String name;
  String magicCode;
  String magic;
  List<Pet> pets;
  String header;
  String countLetter;
  String tailMarker;

  /// 原始（去空白后的）载荷，便于调试与往返比对。
  String payload;
  List<String> notes;

  Map<String, dynamic> toJson() => {
        'name': name,
        'magicCode': magicCode,
        'magic': magic,
        'header': header,
        'countLetter': countLetter,
        'tailMarker': tailMarker,
        'pets': pets.map((p) => p.toJson()).toList(),
      };
}

/// 阵容码相关的错误。与 Python 的 `TeamCodeError` 对应，
/// 所有"无法解析"都走这里，调用方据此提示用户而不是静默出废码。
class TeamCodeException implements Exception {
  TeamCodeException(this.message);
  final String message;
  @override
  String toString() => message;
}
