/// 知识库更新逻辑的测试。
///
/// 这块**必须**有测试：如果更新逻辑有 bug，一次坏下载就会让 App 永久起不来。
/// 所以重点验证的不是"正常路径能跑"，而是**各种失败路径都不破坏现有数据**。
///
/// 做法：把两个外部依赖都注入掉
///   * `assetLoader` -> 内存 Map（不依赖 Flutter rootBundle）
///   * `poster`      -> 内存路由（不真的发网络请求）
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/http_client.dart';
import 'package:rocodesk/core/knowledge/bundle_store.dart';
import 'package:rocodesk/core/knowledge/knowledge_base.dart';
import 'package:rocodesk/core/knowledge/manifest.dart';

/// 内存实现，便于精确控制缓存内容与状态。
class MemoryStore implements BundleStore {
  MemoryStore([Map<String, String>? initial]) : _m = {...?initial};

  final Map<String, String> _m;

  /// 记录写入次数，用来断言"失败时不应该发生写入"。
  int writes = 0;

  @override
  String get location => 'memory';

  @override
  Future<String?> read(String name) async => _m[name];

  @override
  Future<void> write(String name, String content) async {
    writes++;
    _m[name] = content;
  }

  @override
  Future<void> clear() async => _m.clear();

  Map<String, String> get snapshot => Map.unmodifiable(_m);
}

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

/// 造一份最小的、结构合法的知识库文件集合。
///
/// 键名是 `CodecTables` 真正会读的那些（不是随便编的），
/// 这样 `_tablesFromStrings` 能解析通过 —— 否则测不出真实行为。
Map<String, String> _validBundle() => {
      'pets.json': jsonEncode({
        'by_code': {'wz': '雪影娃娃'},
        'by_name': {'雪影娃娃': 'wz'},
      }),
      'skills.json': jsonEncode({
        'by_code': {'ax9I': '抓挠'},
        'by_name': {'抓挠': 'ax9I'},
      }),
      'natures.json': jsonEncode({
        'by_letter': {'C': '固执'},
        'by_name': {'固执': 'C'},
        'data': [
          {'name': '固执', 'up': '物攻', 'down': '魔攻'},
        ],
      }),
      'codec.json': jsonEncode({
        'evs': {'生命': 'BP'},
        'evsRev': {'BP': '生命'},
        'bloodline': {'T': '首领血脉'},
        'bloodlineAlias': {'首领': 'T'},
        'magic': {'ZZH': '进化之力'},
        'magicRev': {'进化之力': 'ZZH'},
        'dimLetters': {'B': '生命'},
        'seg': '~',
        'emptySkill': '00000',
        'emptySkillSeg': 'none',
        'tailMarker': 'F',
        'header': 'B',
        'defaults': {
          'evCode': 'BPBRBU',
          'natureLetter': 'V',
          'bloodlineLetter': 'T',
          'bloodlineText': '默认血脉',
          'magicName': '进化之力',
          'teamName': '未命名队伍',
          'unknownPet': '未知宠物',
          'unknownSkill': '未知技能',
        },
        'evOrder': ['生命'],
        'evThirdGlobal': [
          ['速度', 0.5],
        ],
        'secondByFirst': <String, dynamic>{},
        'evSecondByFirst': <String, dynamic>{},
        'evThirdByPair': <String, dynamic>{},
      }),
      // 可选文件，但既然 kBundleFiles 里列了它，夹具也要有，
      // 否则更新逻辑会认为"远程清单缺少文件"。
      'variant_types.json': jsonEncode({
        'note': 'test fixture',
        'all': {
          'vi': {'name': '卡瓦重（草地附近的样子）', 'types': ['草']},
          'zg': {'name': '卡瓦重（雪山附近的样子）', 'types': ['草', '冰']},
        },
        'ambiguous_bases': ['卡瓦重'],
        'ambiguous_base_count': 1,
        'covered_codes': 2,
      }),
      'learnsets.json': jsonEncode({
        'note': 'test fixture',
        'by_pet': {
          'wz': ['ax9I'],
        },
        'covered_pets': 1,
      }),
      'bloodline_ranks.json': jsonEncode({
        'note': 'test fixture',
        'ranks': {
          '雪影娃娃': ['T', 'H'],
        },
      }),
    };

String _manifestJson(Map<String, String> files, int version) => jsonEncode({
      'version': version,
      'generated_at': '2026-10-06T00:00:00+08:00',
      'files': {
        for (final e in files.entries)
          e.key: {'sha256': _sha(e.value), 'bytes': e.value.length},
      },
    });

/// 测试用的内置资产：从 Map 里取，不依赖 Flutter 的 rootBundle。
/// 同时让「内置版本号」在测试里可控。
AssetTextLoader _fakeAssets(Map<String, String> files, {int version = 1}) {
  final all = <String, String>{
    ...files,
    'manifest.json': _manifestJson(files, version),
  };
  return (path) async {
    final v = all[path.split('/').last];
    if (v == null) throw StateError('asset not found: $path');
    return v;
  };
}

/// 假 HTTP 层：按路径最后一段路由，可指定某些文件返回 500。
HttpPost _fakePost(Map<String, String> route, {Set<String>? failWith500}) {
  return (url, {required headers, required body}) async {
    final name = url.split('/').last;
    if (failWith500?.contains(name) ?? false) {
      return const HttpResult(statusCode: 500, body: 'boom');
    }
    final v = route[name];
    if (v == null) return const HttpResult(statusCode: 404, body: '');
    return HttpResult(statusCode: 200, body: v);
  };
}

void main() {
  group('manifest 解析', () {
    test('内置格式（files 是对象）能解析，且方向正确', () {
      final files = _validBundle();
      final m = KnowledgeManifest.decode(_manifestJson(files, 7));
      expect(m.version, 7);
      expect(m.files.length, files.length);
      expect(m.file('pets.json')!.sha256, _sha(files['pets.json']!));
      expect(m.file('nope.json'), isNull);
    });

    test('远程格式（files 是数组）也能解析', () {
      final m = KnowledgeManifest.fromJson({
        'version': 3,
        'generated_at': 'x',
        'files': [
          {'name': 'pets.json', 'sha256': 'aa', 'bytes': 1},
        ],
      });
      expect(m.version, 3);
      expect(m.file('pets.json')!.sha256, 'aa');
    });

    test('缺字段不崩，退化成默认值', () {
      final m = KnowledgeManifest.fromJson(const {});
      expect(m.version, 0);
      expect(m.files, isEmpty);
    });

    test('往返一致', () {
      final m = KnowledgeManifest.decode(_manifestJson(_validBundle(), 5));
      final again = KnowledgeManifest.decode(jsonEncode(m.toJson()));
      expect(again.version, m.version);
      expect(again.files.length, m.files.length);
    });
  });

  group('缓存加载', () {
    test('缓存版本更高且 hash 全对 -> 使用缓存', () async {
      final files = _validBundle();
      final kb = KnowledgeBase(
        store: MemoryStore({...files, 'manifest.json': _manifestJson(files, 9)}),
        assetLoader: _fakeAssets(files, version: 1),
      );
      final loaded = await kb.load();
      expect(loaded.fromCache, isTrue, reason: '缓存 9 > 内置 1，应当采用缓存');
      expect(loaded.manifest.version, 9);
      expect(loaded.tables.petNames['wz'], '雪影娃娃');
    });

    test('缓存版本不高于内置 -> 用内置', () async {
      final files = _validBundle();
      final kb = KnowledgeBase(
        store: MemoryStore({...files, 'manifest.json': _manifestJson(files, 1)}),
        assetLoader: _fakeAssets(files, version: 5),
      );
      final loaded = await kb.load();
      expect(loaded.fromCache, isFalse);
      expect(loaded.manifest.version, 5);
    });

    test('缓存内容被篡改 -> 拒绝，且不抛异常', () async {
      final files = _validBundle();
      final tampered = {...files, 'pets.json': '{"by_code":{},"by_name":{}}'};
      final kb = KnowledgeBase(
        // manifest 里记的是**原始** hash，内容却换过了
        store: MemoryStore({...tampered, 'manifest.json': _manifestJson(files, 9)}),
        assetLoader: _fakeAssets(files, version: 1),
      );
      final loaded = await kb.load();
      expect(loaded.fromCache, isFalse, reason: 'hash 不匹配必须拒绝缓存');
      expect(loaded.tables.petNames['wz'], '雪影娃娃', reason: '应当回退到内置数据');
    });

    test('缓存缺文件 -> 拒绝', () async {
      final files = _validBundle();
      final partial = Map<String, String>.from(files)..remove('skills.json');
      final kb = KnowledgeBase(
        store: MemoryStore({...partial, 'manifest.json': _manifestJson(files, 9)}),
        assetLoader: _fakeAssets(files, version: 1),
      );
      expect((await kb.load()).fromCache, isFalse);
    });

    test('缓存 manifest 本身损坏 -> 拒绝', () async {
      final files = _validBundle();
      final kb = KnowledgeBase(
        store: MemoryStore({...files, 'manifest.json': '{ this is not json'}),
        assetLoader: _fakeAssets(files, version: 1),
      );
      expect((await kb.load()).fromCache, isFalse);
    });

    test('缓存 hash 自洽但结构不对 -> 拒绝', () async {
      // 所有文件 hash 都自洽，但 codec.json 缺必要键
      final bad = _validBundle();
      bad['codec.json'] = '{"unexpected":true}';
      final kb = KnowledgeBase(
        store: MemoryStore({...bad, 'manifest.json': _manifestJson(bad, 9)}),
        assetLoader: _fakeAssets(_validBundle(), version: 1),
      );
      final loaded = await kb.load();
      expect(loaded.fromCache, isFalse,
          reason: 'hash 只证明"内容没被改过"，不证明"结构可用"');
    });
  });

  group('更新检查：失败路径绝不能破坏现有数据', () {
    KnowledgeBase kbWith(
      HttpPost post,
      MemoryStore store, {
      Map<String, String>? assets,
      int assetVersion = 1,
    }) =>
        KnowledgeBase(
          store: store,
          poster: post,
          remoteManifestUrl: 'https://example.test/kb/manifest.json',
          assetLoader: _fakeAssets(assets ?? _validBundle(), version: assetVersion),
        );

    test('未配置远程地址 -> disabled，不发请求', () async {
      var called = false;
      final kb = KnowledgeBase(
        store: MemoryStore(),
        assetLoader: _fakeAssets(_validBundle()),
        poster: (u, {required headers, required body}) async {
          called = true;
          return const HttpResult(statusCode: 200, body: '{}');
        },
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.disabled);
      expect(called, isFalse, reason: '没配地址就不该发网络请求');
    });

    test('enabled=false 时直接跳过', () async {
      var called = false;
      final kb = KnowledgeBase(
        store: MemoryStore(),
        assetLoader: _fakeAssets(_validBundle()),
        remoteManifestUrl: 'https://example.test/kb/manifest.json',
        poster: (u, {required headers, required body}) async {
          called = true;
          return const HttpResult(statusCode: 200, body: '{}');
        },
      );
      final r = await kb.checkForUpdate(enabled: false);
      expect(r.outcome, UpdateOutcome.disabled);
      expect(called, isFalse);
    });

    test('远端版本不高于本地 -> upToDate，不写任何东西', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(files, 1)}),
        store,
        assetVersion: 5,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.upToDate);
      expect(store.writes, 0, reason: '没有新版本就不该写缓存');
    });

    test('远端不可达 -> unreachable，本地不受影响', () async {
      final store = MemoryStore();
      final kb = kbWith(
        (u, {required headers, required body}) async =>
            throw const _HttpFailureStub(),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.unreachable);
      expect(store.writes, 0);
      expect((await kb.load()).fromCache, isFalse, reason: '应当仍能用内置数据');
    });

    test('远端 HTTP 500 -> unreachable，不写', () async {
      final store = MemoryStore();
      final kb = kbWith(
        (u, {required headers, required body}) async =>
            const HttpResult(statusCode: 500, body: ''),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.unreachable);
      expect(store.writes, 0);
    });

    test('远端 manifest 不是 JSON -> 不写', () async {
      final store = MemoryStore();
      final kb = kbWith(_fakePost({'manifest.json': 'not json at all'}), store);
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.unreachable);
      expect(store.writes, 0);
    });

    test('远端清单缺文件 -> badManifest，不写', () async {
      final files = _validBundle();
      final incomplete = Map<String, String>.from(files)..remove('natures.json');
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({
          'manifest.json': _manifestJson(incomplete, 99),
          ...incomplete,
        }),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.badManifest);
      expect(store.writes, 0);
    });

    test('某个文件下载 500 -> 整批放弃，**一个字节都不写**', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({
          'manifest.json': _manifestJson(files, 99),
          ...files,
        }, failWith500: {'skills.json'}),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.unreachable);
      expect(store.writes, 0, reason: '半套数据比旧数据更糟：必须整批成功才落盘');
    });

    test('文件内容与清单 hash 不符 -> hashMismatch，一个字节都不写', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final served = {...files, 'pets.json': '{"by_code":{},"by_name":{}}'};
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(files, 99), ...served}),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.hashMismatch);
      expect(store.writes, 0);
    });

    test('hash 对但结构不合法 -> badManifest，不落盘', () async {
      final files = _validBundle();
      final broken = {...files, 'codec.json': '{"unexpected":true}'};
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(broken, 99), ...broken}),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.badManifest);
      expect(store.writes, 0, reason: '解析不了的数据绝不能落盘');
    });

    test('全部通过 -> updated，写入文件数正确', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(files, 42), ...files}),
        store,
      );
      final r = await kb.checkForUpdate();
      expect(r.outcome, UpdateOutcome.updated);
      expect(r.fromVersion, 1);
      expect(r.toVersion, 42);
      expect(store.writes, files.length + 1, reason: '4 个数据文件 + 1 个 manifest');
    });

    test('更新成功后再次加载会用上新版本', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(files, 42), ...files}),
        store,
      );
      await kb.checkForUpdate();
      final loaded = await kb.load();
      expect(loaded.fromCache, isTrue);
      expect(loaded.manifest.version, 42);
    });

    test('两次检查同一版本不会重复下载（幂等）', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(files, 42), ...files}),
        store,
      );
      expect((await kb.checkForUpdate()).outcome, UpdateOutcome.updated);
      final after = store.writes;

      expect((await kb.checkForUpdate()).outcome, UpdateOutcome.upToDate);
      expect(store.writes, after, reason: '第二次不该再写');
    });

    test('resetToBundled 之后回到内置版本', () async {
      final files = _validBundle();
      final store = MemoryStore();
      final kb = kbWith(
        _fakePost({'manifest.json': _manifestJson(files, 42), ...files}),
        store,
      );
      await kb.checkForUpdate();
      expect((await kb.load()).fromCache, isTrue);

      await kb.resetToBundled();
      final after = await kb.load();
      expect(after.fromCache, isFalse);
      expect(after.manifest.version, 1, reason: '应当回到内置版本');
    });

    test('超时会中止并归类为不可达', () async {
      final store = MemoryStore();
      final kb = kbWith(
        (u, {required headers, required body}) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return const HttpResult(statusCode: 200, body: '{}');
        },
        store,
      );
      final r = await kb.checkForUpdate(
        timeout: const Duration(milliseconds: 50),
      );
      expect(r.outcome, UpdateOutcome.unreachable);
      expect(store.writes, 0);
    });
  });
}

/// 只用于触发 catch 分支的假异常。
class _HttpFailureStub implements Exception {
  const _HttpFailureStub();
  @override
  String toString() => 'network down';
}
