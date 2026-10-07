/// 识别提示词：从资产来，且能被注入。
///
/// ## 为什么提示词离开代码值得单独测
///
/// 它是这个项目里最长的中文文本（原来 76 行塞在 `vlm_client.dart` 里），
/// 而且**改动的频率远高于调用它的代码** —— 调措辞、加例子、修歧义。
/// 放进资产后有两个新的失败方式，都必须钉住：
///
///   1. **资产漏打包**：pubspec 的 assets 段忘了写，运行时读不到。
///      这类失败是静默的（退回 fallback，功能"看着还能跑"，准确率掉了）。
///   2. **提示词被截断**：资产文件写到一半存盘、或编码出错。
///      提示词缺了「性格箭头表」这种关键段，模型会开始编性格名。
///
/// 另外验证 `VlmClient` 是**接受**提示词而不是自己读资产 ——
/// 那样它才能在纯 Dart 测试里跑，也才能按场景换提示词。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/http_client.dart';
import 'package:rocodesk/core/prompts.dart';
import 'package:rocodesk/core/vlm_client.dart';

const _assetPath = 'assets/prompts/recognize_team.txt';

void main() {
  group('资产本身', () {
    test('文件存在、非空、是 UTF-8 可读文本', () {
      final f = File(_assetPath);
      expect(f.existsSync(), isTrue,
          reason: '找不到 $_assetPath —— 提示词资产被删或路径改了');

      final bytes = f.readAsBytesSync();
      expect(bytes.length, greaterThan(500),
          reason: '提示词只有 ${bytes.length} 字节，像是被截断了');

      final text = utf8.decode(bytes);
      expect(text.trim(), isNotEmpty);
    });

    test('关键段落都在（缺哪段都会让模型开始编）', () {
      final text = File(_assetPath).readAsStringSync();
      // 这些段是"模型不编"的护栏，缺一段就是一次准确率事故
      for (final section in const [
        '【图上的布局】',
        '【系别与血脉图标（重要）】',
        '【性格读法（重要）】',
        '【名字要写完整（重要）】',
        '【个体资质】',
        '【要求】',
      ]) {
        expect(text.contains(section), isTrue, reason: '缺段落：$section');
      }
    });

    test('30 条性格箭头对照表是完整的', () {
      final text = File(_assetPath).readAsStringSync();
      // 格式：`物攻↑物防↓ = 大胆`
      final pairs = RegExp(r'[^\s↑]+↑[^\s↓]+↓\s*=\s*\S+').allMatches(text);
      expect(pairs.length, 30,
          reason: '箭头对照表应当有 30 条，实际 ${pairs.length} 条 —— '
              '缺条会让模型自己编性格名');
    });

    test('18 个系别与 24 条血脉的名字都在提示词里', () {
      final text = File(_assetPath).readAsStringSync();
      const types = [
        '普通', '火', '水', '草', '电', '冰', '武', '毒', '地',
        '翼', '萌', '虫', '幻', '幽', '恶', '龙', '机械', '光',
      ];
      for (final t in types) {
        expect(text.contains(t), isTrue, reason: '提示词里缺系别「$t」');
      }
      // 6 条特殊血脉必须点名（它们不在系别里）
      for (final b in const ['首领', '巨兽', '黑魔法', '异核', '污染', '奇异']) {
        expect(text.contains(b), isTrue, reason: '提示词里缺特殊血脉「$b」');
      }
    });

    test('pubspec 里声明了这个资产目录', () {
      // 漏声明的失败是静默的：构建成功、运行时报资产不存在 → 退回 fallback
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/prompts/'), isTrue,
          reason: 'pubspec.yaml 的 assets 段没写 assets/prompts/ —— '
              '打包后读不到提示词，会静默退回 fallback');
    });
  });

  group('Prompts.load', () {
    // 这些测试需要 Flutter binding 才能读 rootBundle
    TestWidgetsFlutterBinding.ensureInitialized();

    test('能真的从资产读到（不是打了 fallback）', () async {
      final p = await Prompts.load(useCache: false);
      expect(p.loadedFromAsset, isTrue,
          reason: '退回了 fallback —— 资产没打包成功或路径不对');
      expect(p.recognizeTeam.length, greaterThan(500));
      // fallback 很短，真提示词长得多 —— 用长度再确认一次不是 fallback
      expect(p.recognizeTeam, isNot(contains('读出图中每只精灵的名字、性格')));
    });

    test('读到的内容与源文件一致（没有额外裁剪出问题）', () async {
      final p = await Prompts.load(useCache: false);
      final onDisk = File(_assetPath).readAsStringSync().trimRight();
      expect(p.recognizeTeam, onDisk);
    });

    test('缓存有效：第二次不重读资产', () async {
      final a = await Prompts.load();
      final b = await Prompts.load();
      expect(identical(a, b), isTrue, reason: '应当返回同一个实例');
    });
  });

  group('VlmClient 接受提示词，不自己读资产', () {
    test('systemPrompt 是构造参数，且真的进了请求体', () async {
      String? capturedBody;
      final client = VlmClient(
        baseUrl: 'https://example.invalid',
        apiKey: 'k',
        model: 'm',
        systemPrompt: '测试用提示词',
        poster: (url, {required headers, required body}) async {
          capturedBody = body;
          return const HttpResult(
            statusCode: 200,
            body: '{"choices":[{"message":{"content":"{}"}}]}',
          );
        },
      );

      await client.analyzeImage(Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]));

      expect(capturedBody, isNotNull);
      expect(capturedBody, contains('测试用提示词'),
          reason: '传入的提示词必须出现在请求体里 —— '
              '如果客户端自己读资产，这条会拿到别的内容');
    });

    test('Prompts.forTest 提供一个不碰资产的实例', () {
      final p = Prompts.forTest('任意提示词');
      expect(p.recognizeTeam, '任意提示词');
      expect(p.loadedFromAsset, isTrue);
    });
  });
}
