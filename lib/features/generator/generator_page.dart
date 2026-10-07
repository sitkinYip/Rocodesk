/// 「生成」页：截图 -> 阵容码 + 给官方助手的描述。
///
/// 这是当前唯一完整的功能，所以独占一个 tab。
/// 页面结构按 iOS 的层级走：大标题 -> 图片区 -> 结果区，
/// 不用卡片套卡片，靠留白和分隔表达分组。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/settings.dart';
import '../../core/bloodline_ranks.dart';
import '../../core/codec_tables.dart';
import '../../core/icon_assets.dart';
import '../../core/knowledge/knowledge_base.dart';
import '../../core/knowledge/manifest.dart';
import '../../core/models.dart';
import '../../core/pipeline.dart';
import '../../core/teamcodec.dart';
import '../../core/vlm_client.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';
import 'image_input.dart';
import 'result_view.dart';

class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key, required this.store});

  final SettingsStore store;

  @override
  State<GeneratorPage> createState() => _GeneratorPageState();
}

enum _Stage { idle, analyzing, done, failed }

class _GeneratorPageState extends State<GeneratorPage> {
  PickedImage? _image;
  _Stage _stage = _Stage.idle;
  String _error = '';

  CodecTables? _tables;
  TeamCodec? _codec;

  /// 知识库来源与版本，用于在界面上说明"当前用的是哪份数据"。
  String _kbSource = '';
  int _kbVersion = 0;
  String _kbUpdateNote = '';

  RecognizedTeam? _recognized;
  String _code = '';
  String _codeError = '';
  String _aiText = '';
  String? _loadError;

  /// 用户手动纠正过的血脉，键是「第几只」（从 1 开始）。
  final Map<int, String> _bloodlineOverrides = {};

  /// 用户手动选定的形态（精灵码），键是「第几只」（从 1 开始）。
  ///
  /// 用于名字有多个形态、自动消歧也判不出来的情况 ——
  /// 用户点一下就解决，不需要重新识别。
  final Map<int, String> _variantOverrides = {};

  /// 用户修正过的技能表，键是「第几只」（从 1 开始）。
  ///
  /// 用于 OCR 读错技能名的情况（实测「筛管奔流」被读成「藤蔓奔流」）。
  /// 只改这一个技能，不动其他字段，也不需要重新调模型。
  final Map<int, List<String>> _skillOverrides = {};

  /// 用户手动改过的魔法名。为空表示用模型识别的结果。
  String? _magicOverride;

  /// 用户换掉的精灵（精灵码），键是「第几只」。
  final Map<int, String> _petOverrides = {};

  /// 用户改过的性格，键是「第几只」。
  final Map<int, String> _natureOverrides = {};

  /// 用户改过的个体资质，键是「第几只」。
  final Map<int, List<String>> _evOverrides = {};

  /// 用户手动改过的队伍名。为空表示用识别结果。
  ///
  /// 注意：队伍名**不进阵容码**，只影响展示和导出的文本。
  String? _teamNameOverride;

  /// 纠错面板用的参考图标。载入失败也不影响功能（面板退化成纯文字）。
  IconAssets _icons = IconAssets.empty();

  /// 血脉候选的本地排序。为空则选择器按字母序。
  BloodlineRanks _bloodlineRanks = BloodlineRanks.empty();

  /// 供测试与界面使用：当前图标资源。
  IconAssets get icons => _icons;

  /// 这只精灵能学的技能名，供手动填写时提示范围。
  List<String> _learnableFor(RecognizedPet pet) {
    final t = _tables;
    if (t == null) return const [];
    final code = _variantOverrides[_petIndexOf(pet)]?.isNotEmpty == true
        ? _variantOverrides[_petIndexOf(pet)]!
        : pet.petId;
    return t.skillMatcher.learnableNames(code);
  }

  int _petIndexOf(RecognizedPet pet) {
    final rt = _recognized;
    if (rt == null) return -1;
    final i = rt.pets.indexOf(pet);
    return i < 0 ? -1 : i + 1;
  }

  /// 用户改完技能 -> 就地重新出码。
  void _applySkillFix(int index, List<String> skills) {
    setState(() {
      _skillOverrides[index] = skills;
      // 改过的技能不再是"疑似读错"，把那条提示收起来
      final rt = _recognized;
      if (rt != null && index - 1 < rt.pets.length) {
        final p = rt.pets[index - 1];
        for (final s in skills) {
          p.skillSuggestions.remove(s);
        }
      }
    });
    _reencode();
  }

  /// 用户改了魔法 -> 就地重新出码。
  void _applyMagicFix(String? magic) {
    setState(() => _magicOverride = magic);
    _reencode();
  }

  /// 用户换了精灵 -> 就地重新出码。
  ///
  /// 换精灵时把这一只的其他覆盖留下（技能/性格/资质）—— 用户可能先改了
  /// 那些再换精灵；技能学不学得了由界面提示，不在这里悄悄清掉。
  void _applyPetFix(int index, String petId) {
    setState(() => _petOverrides[index] = petId);
    _reencode();
  }

  /// 用户改了性格 -> 就地重新出码。
  void _applyNatureFix(int index, String nature) {
    setState(() => _natureOverrides[index] = nature);
    _reencode();
  }

  /// 用户改了个体资质 -> 就地重新出码。
  void _applyEvsFix(int index, List<String> evs) {
    setState(() => _evOverrides[index] = evs);
    _reencode();
  }

  /// 用户改了队伍名 -> 就地重新生成导出文本。
  ///
  /// 队伍名不进阵容码，所以其实只需重算文本；走同一条路径省得两处逻辑分叉。
  void _applyTeamName(String? name) {
    setState(() => _teamNameOverride = name);
    _reencode();
  }

  /// 当前生效的队伍名。
  String get _effectiveTeamName {
    final o = _teamNameOverride;
    if (o != null && o.isNotEmpty) return o;
    final rt = _recognized;
    return (rt != null && rt.teamName.isNotEmpty) ? rt.teamName : '未命名队伍';
  }

  /// 可选的魔法列表（从知识库的 magic 表来，不写死）。
  List<String> get _magicOptions {
    final t = _tables;
    if (t == null) return const [];
    return t.magic.values.toList();
  }

  /// 当前生效的魔法名。
  String get _effectiveMagic {
    if (_magicOverride != null && _magicOverride!.isNotEmpty) {
      return _magicOverride!;
    }
    final rt = _recognized;
    return (rt != null && rt.magic.isNotEmpty) ? rt.magic : '进化之力';
  }

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadIcons();
  }

  /// 载入参考图标。与资料表分开：图标缺失不该拖慢或挡住主流程。
  ///
  /// **必须包 try/catch**：这是启动期的异步任务，一旦抛出就是未捕获异常，
  /// 而 AppShell 用 IndexedStack 会同时构建三个页面 ——
  /// 任何一个页面抛异常，整屏就白，用户只看到一片空白，没有任何提示。
  /// 图标只是可选增强，绝不能因为它把整个应用弄崩。
  Future<void> _loadIcons() async {
    try {
      final icons = await IconAssets.load();
      final ranks = await BloodlineRanks.load();
      if (!mounted) return;
      setState(() {
        _icons = icons;
        _bloodlineRanks = ranks;
      });
    } catch (e) {
      // 安静降级：纠错面板没有图标看，但功能照常
      if (!mounted) return;
      setState(() {
        _icons = IconAssets.empty();
        _bloodlineRanks = BloodlineRanks.empty();
      });
    }
  }

  /// 加载知识库并可选地检查更新。
  ///
  /// 顺序刻意如此：
  ///   1. 先加载**本地**数据（内置或上次缓存的），立刻可用于识别；
  ///   2. 再**后台**检查远程更新，成功了只提示"重启后生效"，不打断当前操作。
  ///
  /// 为什么不先检查再加载：网络慢或断网会让启动卡住。
  /// 离线可用是这个功能的第一原则。
  Future<void> _loadTables() async {
    try {
      final s = widget.store.settings;
      final kb = KnowledgeBase(remoteManifestUrl: s.knowledgeUrl);

      final loaded = await kb.load();
      if (!mounted) return;
      setState(() {
        _tables = loaded.tables;
        _codec = TeamCodec(loaded.tables);
        _kbSource = loaded.fromCache ? '本地缓存' : '内置';
        _kbVersion = loaded.manifest.version;
      });

      // 后台检查更新：不 await 在关键路径上，失败也不影响使用
      if (s.canCheckKnowledge) {
        unawaited(_checkKbUpdate(kb, loaded.manifest.version));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '资料表加载失败：$e');
    }
  }

  Future<void> _checkKbUpdate(KnowledgeBase kb, int currentVersion) async {
    final report = await kb.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _kbUpdateNote = switch (report.outcome) {
        UpdateOutcome.updated =>
          '发现新数据 v${report.toVersion}，重启后生效',
        UpdateOutcome.upToDate => '',
        // 下面这些都**不是错误**，只是没更新成功，不该打扰用户
        UpdateOutcome.unreachable => '',
        UpdateOutcome.disabled => '',
        UpdateOutcome.badManifest => '远程数据格式不对，已忽略',
        UpdateOutcome.hashMismatch => '远程数据校验失败，已忽略',
      };
    });
  }

  bool get _busy => _stage == _Stage.analyzing;

  void _onPicked(PickedImage img) {
    setState(() {
      _image = img;
      _recognized = null;
      _code = '';
      _codeError = '';
      _aiText = '';
      _error = '';
      _stage = _Stage.idle;
      _bloodlineOverrides.clear();
    });
    if (widget.store.settings.autoAnalyze && widget.store.isReady) {
      _analyze();
    }
  }

  Future<void> _analyze() async {
    final img = _image;
    if (img == null) return;

    final s = widget.store.settings;
    if (!s.isReady) {
      setState(() {
        _stage = _Stage.failed;
        _error = '还没配置模型。请到「设置」填写 API Key 后重试。';
      });
      return;
    }
    final codec = _codec;
    final tables = _tables;
    if (codec == null || tables == null) {
      setState(() {
        _stage = _Stage.failed;
        _error = _loadError ?? '资料表还在加载，稍等一下再试。';
      });
      return;
    }

    setState(() {
      _stage = _Stage.analyzing;
      _error = '';
      _recognized = null;
      _code = '';
      _codeError = '';
      _aiText = '';
    });

    try {
      final client = VlmClient(
        baseUrl: s.effectiveBaseUrl,
        apiKey: s.apiKey,
        model: s.effectiveModel,
      );
      final res = await client.analyzeImage(img.bytes);
      final rt = normalizeVlmOutput(res.parsed, codec: codec, tables: tables);
      final (code, codeErr, aiText) = _encode(rt, codec);
      if (!mounted) return;
      setState(() {
        _recognized = rt;
        _code = code;
        _codeError = codeErr;
        _aiText = aiText;
        _stage = _Stage.done;
      });
    } on VlmException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = '识别出错：$e';
      });
    }
  }

  /// 编码。失败时返回人类可读的原因，而不是抛到界面上。
  (String, String, String) _encode(RecognizedTeam rt, TeamCodec codec) {
    // 注意：判断"能否出码"时要**把用户已选的形态算进去** ——
    // 否则用户选完形态仍然被"有精灵没对上图鉴"挡住。
    final unresolved = <String>[];
    for (var i = 0; i < rt.pets.length; i++) {
      final chosen = _variantOverrides[i + 1];
      if (chosen != null && chosen.isNotEmpty) continue;
      if (!rt.pets[i].resolved) unresolved.add(rt.pets[i].name);
    }
    if (rt.pets.isEmpty) {
      return ('', '没有识别到任何精灵。', '');
    }
    if (unresolved.isNotEmpty) {
      return ('', '有 ${unresolved.length} 只精灵没能对上图鉴（${unresolved.join('、')}），'
          '无法生成阵容码。请在下面选择它们的形态。', '');
    }
    try {
      final team = toCodecTeam(
        rt,
        _bloodlineOverrides,
        variantOverrides: _variantOverrides,
        skillOverrides: _skillOverrides,
        magicOverride: _magicOverride,
        teamNameOverride: _teamNameOverride,
        petOverrides: _petOverrides,
        natureOverrides: _natureOverrides,
        evOverrides: _evOverrides,
        tables: _tables,
      );
      final code = codec.encode(team);
      final aiText = codec.toGameText(team);
      // 把编码过程中产生的补位/默认值提示带回到界面上。
      // 这些是"系统替你猜的"信息，必须让用户看到，不能悄悄用。
      //
      // 两点注意：
      //   1. 过滤掉技术性噪音（如"血脉字母为 A 语义未证实"）——
      //      那是正常状态，不需要用户操作，而且每次重编码都会重复追加。
      //   2. 按内容去重，因为改一次设置就会重跑一遍 _encode。
      for (var i = 0; i < team.pets.length && i < rt.pets.length; i++) {
        final p = rt.pets[i];
        for (final note in team.pets[i].notes) {
          if (isCodecNoise(note)) continue;
          if (p.warnings.contains(note)) continue;
          p.warnings.add(note);
        }
      }
      return (code, '', aiText);
    } on TeamCodeException catch (e) {
      return ('', e.message, '');
    }
  }

  /// 用户选定了某只精灵的形态 -> 立刻重新出码，不用重新识别。
  void _chooseVariant(int index, String code) {
    setState(() {
      _variantOverrides[index] = code;
      // 选了形态之后，之前那条"选一个"的提示就过期了
      final rt = _recognized;
      if (rt != null && index - 1 < rt.pets.length) {
        rt.pets[index - 1].warnings
            .removeWhere((w) => w.contains('请在下面选一个'));
      }
    });
    _reencode();
  }

  void _reencode() {
    final rt = _recognized;
    final codec = _codec;
    if (rt == null || codec == null) return;
    final (code, err, aiText) = _encode(rt, codec);
    setState(() {
      _code = code;
      _codeError = err;
      _aiText = aiText;
    });
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 这个页面是被 push 打开的（入口在「工具」页的卡片上），
    // 所以要有 AppBar 提供返回按钮 —— 用户得能退回工具列表。
    return Scaffold(
      appBar: AppBar(
        title: const Text('一图流生成阵容码'),
        // 返回按钮是 push 路由的默认行为，不要自己画
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: [
          if (_kbVersion > 0) ...[
            Row(
              children: [
                Icon(Icons.storage_outlined,
                    size: 13, color: context.colors.textTertiary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '资料库 $_kbSource · v$_kbVersion',
                  style: TextStyle(
                    fontSize: AppType.sCaption,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_kbUpdateNote.isNotEmpty) ...[
            InlineNotice(
              message: _kbUpdateNote,
              severity: NoticeSeverity.info,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          if (_loadError != null) ...[
            InlineNotice(message: _loadError!, severity: NoticeSeverity.error),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ---------- 图片 ----------
        ImageDropZone(
          image: _image,
          busy: _busy,
          onPicked: _onPicked,
          onCleared: () => setState(() {
            _image = null;
            _stage = _Stage.idle;
            _recognized = null;
            _code = '';
            _error = '';
          }),
        ),

        if (_image != null && _stage != _Stage.done) ...[
          const SizedBox(height: AppSpacing.lg),
          _analyzeButton(),
        ],

        // ---------- 错误 ----------
        if (_stage == _Stage.failed) ...[
          const SizedBox(height: AppSpacing.lg),
          InlineNotice(
            message: _error,
            severity: NoticeSeverity.error,
            action: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('设置')),
                    body: _SettingsShortcut(store: widget.store),
                  ),
                ),
              ),
              child: const Text('去设置'),
            ),
          ),
        ],

        // ---------- 结果 ----------
        if (_stage == _Stage.analyzing) ...[
          const SizedBox(height: AppSpacing.xl),
          const _AnalyzingSkeleton(),
        ],

        if (_stage == _Stage.done && _recognized != null) ...[
          const SizedBox(height: AppSpacing.xl),
          ResultView(
            team: _recognized!,
            code: _code,
            codeError: _codeError,
            aiText: _aiText,
            bloodlineOverrides: _bloodlineOverrides,
            variantOverrides: _variantOverrides,
            skillOverrides: _skillOverrides,
            learnableSkills: _learnableFor,
            magic: _effectiveMagic,
            magicOptions: _magicOptions,
            teamName: _effectiveTeamName,
            icons: _icons,
            bloodlineRanks: _bloodlineRanks,
            onChooseMagic: _applyMagicFix,
            onEditTeamName: _applyTeamName,
            onChooseVariant: _chooseVariant,
            onSkillsChanged: _applySkillFix,
            onOverrideBloodline: (index, letter) {
              setState(() {
                if (letter == null) {
                  _bloodlineOverrides.remove(index);
                } else {
                  _bloodlineOverrides[index] = letter;
                }
              });
              _reencode();
            },
            onCopy: _copy,
            // 识别页：码是产出，所以给「复制走」和「识别错了重来」两个动作
            onCopyCode: _copy,
            onPrimaryAction: _analyze,
            // ---- 整队可编辑 ----
            // 用户要的是"拿到一图流之后还能自己搭配"，所以精灵、性格、
            // 个体资质、血脉、技能全部开放修改，而不只是修正识别错误。
            tables: _tables,
            petOverrides: _petOverrides,
            natureOverrides: _natureOverrides,
            evOverrides: _evOverrides,
            onPetChanged: _applyPetFix,
            onNatureChanged: _applyNatureFix,
            onEvsChanged: _applyEvsFix,
          ),
        ],
        ],
      ),
    );
  }

  Widget _analyzeButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _analyze,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(_busy ? '识别中' : '开始识别'),
      ),
    );
  }
}

/// 分析中的骨架屏。
/// 用骨架而不是转圈：让用户预期"马上会出现一列卡片"，
/// 而不是一个不知道要等多久的旋转图标。
class _AnalyzingSkeleton extends StatelessWidget {
  const _AnalyzingSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '正在识别截图',
              style: TextStyle(
                fontSize: AppType.sSubhead,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < 3; i++) ...[
          _ShimmerBar(widthFactor: 1.0),
          const SizedBox(height: AppSpacing.sm),
          _ShimmerBar(widthFactor: 0.6),
          if (i < 2) const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}

class _ShimmerBar extends StatefulWidget {
  const _ShimmerBar({required this.widthFactor});
  final double widthFactor;

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.separator;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widget.widthFactor,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: LinearGradient(
                colors: [
                  base,
                  base.withValues(alpha: 0.4),
                  base,
                ],
                stops: [
                  (t - 0.3).clamp(0.0, 1.0),
                  t.clamp(0.0, 1.0),
                  (t + 0.3).clamp(0.0, 1.0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 从错误提示里跳转到设置页时用的小包装。
class _SettingsShortcut extends StatelessWidget {
  const _SettingsShortcut({required this.store});
  final SettingsStore store;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
