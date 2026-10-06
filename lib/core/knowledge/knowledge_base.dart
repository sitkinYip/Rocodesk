/// 知识库加载与更新。
///
/// 完整流程（设计原则：**远程永远不能把 App 弄坏**）：
///
/// ```
/// 启动
///  ├─ 读内置 manifest（assets/data/manifest.json）-> 本地版本 N
///  ├─ 读本地缓存 manifest（如果有）
///  │     └─ 版本 > N 且所有文件 sha256 校验通过 ? 用缓存 : 用内置
///  └─ 后台检查远程 manifest（可选，可关闭，有超时）
///        ├─ 远程版本 <= 当前版本 -> 什么都不做
///        ├─ 下载各文件 -> 校验 sha256 -> 写缓存
///        └─ 任何一步失败 -> 静默保留当前版本，绝不半途替换
/// ```
///
/// 刻意不做的事：
///   * 不做增量/差分下载 —— 总数据量只有几十 KB，差分不值得那套复杂度。
///   * 不做后台静默替换 —— 新数据只在下次启动生效，避免运行中状态突变。
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../codec_tables.dart';
import '../http_client.dart';
import 'bundle_store.dart';
import 'manifest.dart';

/// 知识库包含的文件（与 `tools/export_data_for_app.py` 导出的对应）。
const List<String> kBundleFiles = [
  'pets.json',
  'skills.json',
  'natures.json',
  'codec.json',
  'variant_types.json',
  'learnsets.json',
  // 血脉候选的本地排序。每张图重新生成，不是静态真值；
  // 缺了它选择器退化成字母序，功能不受影响。
  'bloodline_ranks.json',
];

/// 远程 manifest 的默认地址。
///
/// **默认留空 = 不检查更新**，因为现在还没有托管。
/// 等把 `manifest.json` 传到静态托管（jsDelivr / OSS / GitHub Raw 都行）后，
/// 在这里填地址即可，或者由设置页让用户填。
///
/// 注意：这**不需要自建服务器**，一个静态 JSON 文件就够。
const String kDefaultRemoteManifestUrl = '';

class KnowledgeException implements Exception {
  KnowledgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 加载结果：数据表 + 用了哪个版本。
class LoadedKnowledge {
  const LoadedKnowledge({
    required this.tables,
    required this.manifest,
    required this.source,
  });

  final CodecTables tables;
  final KnowledgeManifest manifest;

  /// `bundled` 或 `cached`，用于在设置页说明当前数据来自哪里。
  final String source;

  bool get fromCache => source == 'cached';
}

/// 读取内置资产文本的方式。可注入，便于测试时不依赖 Flutter 的 rootBundle。
typedef AssetTextLoader = Future<String> Function(String assetPath);

Future<String> _defaultAssetLoader(String assetPath) =>
    rootBundle.loadString(assetPath);

class KnowledgeBase {
  KnowledgeBase({
    BundleStore? store,
    HttpPost? poster,
    String? remoteManifestUrl,
    AssetTextLoader? assetLoader,
  })  : _injectedStore = store,
        _post = poster ?? httpPost,
        _remoteUrl = remoteManifestUrl ?? kDefaultRemoteManifestUrl,
        _loadAsset = assetLoader ?? _defaultAssetLoader;

  /// 外部注入的 store（测试用）。为空时按平台惰性创建。
  /// 刻意不在构造时创建：Web 端创建 store 会碰 localStorage，不该在构造期做 IO。
  final BundleStore? _injectedStore;
  BundleStore? _openedStore;
  final HttpPost _post;
  final String _remoteUrl;
  final AssetTextLoader _loadAsset;

  KnowledgeManifest? _bundledManifest;

  /// 读取内置 manifest。
  Future<KnowledgeManifest> bundledManifest() async {
    if (_bundledManifest != null) return _bundledManifest!;
    try {
      final text = await _loadAsset('assets/data/manifest.json');
      _bundledManifest = KnowledgeManifest.decode(text);
    } catch (e) {
      // 内置 manifest 缺失不该让 App 起不来：退化成一个版本 0 的空清单。
      _bundledManifest = const KnowledgeManifest(
        version: 0,
        generatedAt: '',
        files: [],
      );
    }
    return _bundledManifest!;
  }

  Future<BundleStore> _openStore() async =>
      _openedStore ??= _injectedStore ?? await openBundleStore();

  /// 加载知识库。优先用校验通过的缓存，否则用内置资产。
  Future<LoadedKnowledge> load({bool preferCache = true}) async {
    final bundled = await bundledManifest();
    final store = await _openStore();
    await store.read('manifest.json'); // 触发一次读取，便于 Web 端预热

    if (preferCache) {
      final cached = await _tryLoadCached(store, bundled);
      if (cached != null) return cached;
    }

    final tables = await _loadFromAssets(kBundleFiles);
    return LoadedKnowledge(
      tables: tables,
      manifest: bundled,
      source: 'bundled',
    );
  }

  /// 尝试从缓存加载。任何一项校验不过就返回 null（调用方回退内置）。
  Future<LoadedKnowledge?> _tryLoadCached(
    BundleStore store,
    KnowledgeManifest bundled,
  ) async {
    final raw = await store.read('manifest.json');
    if (raw == null) return null;

    final KnowledgeManifest cachedManifest;
    try {
      cachedManifest = KnowledgeManifest.decode(raw);
    } catch (_) {
      return null; // 缓存 manifest 坏了 -> 忽略
    }
    if (cachedManifest.version <= bundled.version) return null;

    // 校验每个文件存在且 hash 对得上
    final contents = <String, String>{};
    for (final name in kBundleFiles) {
      final text = await store.read(name);
      if (text == null) return null;
      final expected = cachedManifest.file(name)?.sha256 ?? '';
      if (expected.isEmpty) return null;
      if (sha256.convert(utf8.encode(text)).toString() != expected) {
        return null; // 内容被改过或写坏了
      }
      contents[name] = text;
    }

    try {
      final tables = _tablesFromStrings(contents);
      return LoadedKnowledge(
        tables: tables,
        manifest: cachedManifest,
        source: 'cached',
      );
    } catch (_) {
      return null; // 结构不对 -> 回退内置
    }
  }

  /// 检查远程是否有新版本。**永远不抛异常**，失败只体现在返回值里。
  ///
  /// `timeout` 是硬性要求：网络卡住不能让启动流程跟着卡住。
  Future<UpdateReport> checkForUpdate({
    Duration timeout = const Duration(seconds: 8),
    bool enabled = true,
  }) async {
    if (!enabled) {
      return const UpdateReport(outcome: UpdateOutcome.disabled);
    }
    if (_remoteUrl.trim().isEmpty) {
      // 还没配置远程地址，属于预期状态，不是错误
      return const UpdateReport(
        outcome: UpdateOutcome.disabled,
        message: '未配置远程更新地址',
      );
    }

    final bundled = await bundledManifest();
    final store = await _openStore();

    // 当前生效版本：缓存里更高的那个，否则内置
    var current = bundled.version;
    final cachedRaw = await store.read('manifest.json');
    if (cachedRaw != null) {
      try {
        final v = KnowledgeManifest.decode(cachedRaw).version;
        if (v > current) current = v;
      } catch (_) {
        // 忽略坏缓存
      }
    }

    final KnowledgeManifest remote;
    try {
      final res = await _post(
        _remoteUrl,
        headers: const {'Accept': 'application/json'},
        body: '',
      ).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return UpdateReport(
          outcome: UpdateOutcome.unreachable,
          fromVersion: current,
          message: '远程返回 ${res.statusCode}',
        );
      }
      remote = KnowledgeManifest.decode(res.body);
    } on TimeoutException {
      return UpdateReport(
        outcome: UpdateOutcome.unreachable,
        fromVersion: current,
        message: '请求超时',
      );
    } catch (e) {
      return UpdateReport(
        outcome: UpdateOutcome.unreachable,
        fromVersion: current,
        message: '$e',
      );
    }

    if (remote.version <= current) {
      return UpdateReport(
        outcome: UpdateOutcome.upToDate,
        fromVersion: current,
        toVersion: remote.version,
      );
    }

    // 下载并校验全部文件。**全部通过才落盘**，避免出现"半套新数据"。
    final staged = <String, String>{};
    for (final name in kBundleFiles) {
      final entry = remote.file(name);
      if (entry == null) {
        return UpdateReport(
          outcome: UpdateOutcome.badManifest,
          fromVersion: current,
          toVersion: remote.version,
          message: '远程清单缺少 $name',
        );
      }
      final url = _resolveRelative(_remoteUrl, name);
      String body;
      try {
        final res = await _post(url, headers: const {}, body: '').timeout(timeout);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return UpdateReport(
            outcome: UpdateOutcome.unreachable,
            fromVersion: current,
            toVersion: remote.version,
            message: '下载 $name 失败（${res.statusCode}）',
          );
        }
        body = res.body;
      } catch (e) {
        return UpdateReport(
          outcome: UpdateOutcome.unreachable,
          fromVersion: current,
          toVersion: remote.version,
          message: '下载 $name 出错：$e',
        );
      }

      final actual = sha256.convert(utf8.encode(body)).toString();
      if (actual != entry.sha256) {
        return UpdateReport(
          outcome: UpdateOutcome.hashMismatch,
          fromVersion: current,
          toVersion: remote.version,
          message: '$name 校验失败（期望 ${entry.sha256.substring(0, 8)}…，'
              '实际 ${actual.substring(0, 8)}…）',
        );
      }
      staged[name] = body;
    }

    // 结构可用性最后一道闸：解析不了就不落盘
    try {
      _tablesFromStrings(staged);
    } catch (e) {
      return UpdateReport(
        outcome: UpdateOutcome.badManifest,
        fromVersion: current,
        toVersion: remote.version,
        message: '下载到的数据无法解析：$e',
      );
    }

    for (final e in staged.entries) {
      await store.write(e.key, e.value);
    }
    await store.write('manifest.json', jsonEncode(remote.toJson()));

    return UpdateReport(
      outcome: UpdateOutcome.updated,
      fromVersion: current,
      toVersion: remote.version,
    );
  }

  /// 清掉缓存，回到内置版本。
  Future<void> resetToBundled() async {
    final store = await _openStore();
    await store.clear();
  }

  /// 缓存位置的可读描述。
  Future<String> cacheLocation() async {
    final store = await _openStore();
    return store.location;
  }

  // ------------------------------------------------------------ 内部工具

  Future<CodecTables> _loadFromAssets(List<String> names) async {
    final map = <String, String>{};
    for (final n in names) {
      map[n] = await _loadAsset('assets/data/$n');
    }
    return _tablesFromStrings(map);
  }

  CodecTables _tablesFromStrings(Map<String, String> map) {
    Map<String, dynamic> dec(String n) {
      final raw = map[n];
      if (raw == null) throw KnowledgeException('缺少文件 $n');
      final v = jsonDecode(raw);
      if (v is! Map<String, dynamic>) {
        throw KnowledgeException('$n 的顶层不是 JSON 对象');
      }
      return v;
    }

    // variant_types.json 是可选文件：老数据包没有它，
    // 缺了只是形态消歧退化成"让用户选"，不该让整包加载失败。
    Map<String, dynamic>? optional(String n) {
      final raw = map[n];
      if (raw == null) return null;
      try {
        final v = jsonDecode(raw);
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    final tables = CodecTables.fromMaps(
      pets: dec('pets.json'),
      skills: dec('skills.json'),
      natures: dec('natures.json'),
      codec: dec('codec.json'),
      variantTypes: optional('variant_types.json'),
      learnsets: optional('learnsets.json'),
    );
    _validateTables(tables);
    return tables;
  }

  /// 显式校验数据表结构。
  ///
  /// 为什么必须有这一步：`CodecTables` 用的是 `late final` **惰性**初始化，
  /// 构造时几乎不报错，缺字段要等到真正用到那一刻才炸。
  /// 那样的话"结构不合法"的数据会被当成合法数据落盘，App 下次启动就崩了。
  /// 所以这里主动把所有关键字段读一遍。
  static void _validateTables(CodecTables t) {
    void need(bool ok, String what) {
      if (!ok) throw KnowledgeException('数据表校验失败：$what');
    }

    need(t.petNames.isNotEmpty, 'pets.json 里没有精灵');
    need(t.petByName.isNotEmpty, 'pets.json 缺少名字反查表');
    need(t.skillNames.isNotEmpty, 'skills.json 里没有技能');
    need(t.skillByName.isNotEmpty, 'skills.json 缺少名字反查表');
    need(t.natureByLetter.isNotEmpty, 'natures.json 缺少 by_letter');
    need(t.natureByName.isNotEmpty, 'natures.json 缺少 by_name');
    need(t.natureData.isNotEmpty, 'natures.json 缺少 data');
    need(t.evs.isNotEmpty, 'codec.json 缺少 evs');
    need(t.evsRev.isNotEmpty, 'codec.json 缺少 evsRev');
    need(t.bloodline.isNotEmpty, 'codec.json 缺少 bloodline');
    need(t.magic.isNotEmpty, 'codec.json 缺少 magic');
    need(t.dimLetters.isNotEmpty, 'codec.json 缺少 dimLetters');
    need(t.seg.isNotEmpty, 'codec.json 缺少 seg');
    need(t.emptySkill.isNotEmpty, 'codec.json 缺少 emptySkill');
    need(t.defaultEvCode.isNotEmpty, 'codec.json 缺少 defaults.evCode');
    need(t.defaultMagicName.isNotEmpty, 'codec.json 缺少 defaults.magicName');
    need(t.unknownPet.isNotEmpty, 'codec.json 缺少 defaults.unknownPet');
    need(t.evOrder.isNotEmpty, 'codec.json 缺少 evOrder');
    // variant_types.json 允许为空（老版本数据包没有它），但要能解析
    if (t.variantHints.isEmpty) {
      // 不是错误：消歧功能退化为"让用户选"，核心功能不受影响
    }
  }

  /// 把 `base` 的最后一段换成 `name`，得到同目录下的文件地址。
  /// 例：`https://cdn/x/manifest.json` + `pets.json` -> `https://cdn/x/pets.json`
  static String _resolveRelative(String base, String name) {
    final i = base.lastIndexOf('/');
    if (i < 0) return name;
    return '${base.substring(0, i + 1)}$name';
  }
}
