/// 自主配队：从零选精灵、血脉、技能，出阵容码与助手指令。
///
/// ## 为什么这个页面这么薄
///
/// 它**没有自己的界面** —— 整个编辑界面复用 `ResultView`（识别页/解析页
/// 用的那个）。这不是偷懒，是刻意的：要让"改一项 → 码跟着变"只有一条实现。
///
/// 于是自主配队实际只是三件事：
///
///   1. 造一个**空队伍**（6 个空槽）
///   2. 把 `ResultView` 的编辑回调接到 [TeamDraft] 上
///   3. 每次改动重算码与助手描述
///
/// 之前实测过这条路走得通：一只精灵能编出 47 字符的码，回解正确
/// （见 `test/builder_page_test.dart`）；`encode` 也支持不足 6 只。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/bloodline_ranks.dart';
import '../../core/codec_tables.dart';
import '../../core/icon_assets.dart';
import '../../core/knowledge/knowledge_base.dart';
import '../../core/pipeline.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';
import '../generator/result_view.dart';
import 'team_draft.dart';

class BuilderPage extends StatefulWidget {
  const BuilderPage({
    super.key,
    this.injectedTables,
    this.initialDraft,
  });

  /// 测试注入，避免每次都要走知识库加载。
  final CodecTables? injectedTables;

  /// 从别处带来的初始队伍（例如把解析结果继续改）。
  /// 为空则从空队伍开始。
  final RecognizedTeam? initialDraft;

  @override
  State<BuilderPage> createState() => _BuilderPageState();
}

class _BuilderPageState extends State<BuilderPage> {
  CodecTables? _tables;
  String _loadError = '';

  IconAssets _icons = IconAssets.empty();
  BloodlineRanks _bloodlineRanks = BloodlineRanks.empty();

  late RecognizedTeam _team;
  final _bloodlineOverrides = <int, String>{};
  final _variantOverrides = <int, String>{};
  final _skillOverrides = <int, List<String>>{};
  final _petOverrides = <int, String>{};
  final _natureOverrides = <int, String>{};
  final _evOverrides = <int, List<String>>{};
  String? _magicOverride;
  String? _teamNameOverride;

  TeamDraft? _draft;

  @override
  void initState() {
    super.initState();
    _team = widget.initialDraft ?? blankTeam();
    _load();
  }

  Future<void> _load() async {
    try {
      // 测试注入了表就直接用，不走知识库
      final injected = widget.injectedTables;
      if (injected != null) {
        setState(() {
          _tables = injected;
          _reencode();
        });
        return;
      }

      final loaded = await KnowledgeBase().load();
      if (!mounted) return;
      setState(() {
        _tables = loaded.tables;
        _reencode();
      });
      // 图标是可选资源：加载失败不影响出码
      final icons = await IconAssets.load();
      final ranks = await BloodlineRanks.load();
      if (!mounted) return;
      setState(() {
        _icons = icons;
        _bloodlineRanks = ranks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '资料表加载失败：$e');
    }
  }

  /// 唯一的重算入口。任何改动都走它 —— 这样"改一项 → 码跟着变"
  /// 只有一个实现，不会出现某个回调忘了重算。
  void _reencode() {
    final t = _tables;
    if (t == null) return;
    _draft = buildDraft(
      _team,
      t,
      bloodlineOverrides: _bloodlineOverrides,
      variantOverrides: _variantOverrides,
      skillOverrides: _skillOverrides,
      petOverrides: _petOverrides,
      natureOverrides: _natureOverrides,
      evOverrides: _evOverrides,
      magicOverride: _magicOverride,
      teamNameOverride: _teamNameOverride,
    );
  }

  /// 这只精灵能学的技能名（候选池要跟着换精灵走）。
  List<String> _learnableFor(RecognizedPet pet) {
    final t = _tables;
    if (t == null) return const [];
    final i = _team.pets.indexOf(pet);
    if (i < 0) return const [];
    final code = effectivePetCode(
      pet,
      petOverride: _petOverrides[i + 1],
      variantOverride: _variantOverrides[i + 1],
    );
    return t.skillMatcher.learnableNames(code);
  }

  Future<void> _copy(String text, String label) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制$label')),
    );
  }

  void _clearAll() {
    setState(() {
      _team = blankTeam();
      _bloodlineOverrides.clear();
      _variantOverrides.clear();
      _skillOverrides.clear();
      _petOverrides.clear();
      _natureOverrides.clear();
      _evOverrides.clear();
      _magicOverride = null;
      _teamNameOverride = null;
      _reencode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _tables;
    final draft = _draft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('自主配队'),
        actions: [
          // 清空是破坏性操作，但代价只是"重新选 6 只"，所以不做二次确认；
          // 给它一个撤销提示就够了。这里直接清，配合 SnackBar 说明。
          IconButton(
            onPressed: draft == null ? null : _clearAll,
            tooltip: '清空重来',
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: [
          if (_loadError.isNotEmpty) ...[
            InlineNotice(message: _loadError, severity: NoticeSeverity.error),
            const SizedBox(height: AppSpacing.lg),
          ],

          if (t == null || draft == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _BuilderHint(filled: draft.filledCount, total: kTeamSize),
            const SizedBox(height: AppSpacing.lg),
            ResultView(
              team: draft.team,
              code: draft.code,
              codeError: draft.codeError,
              aiText: draft.aiText,
              bloodlineOverrides: _bloodlineOverrides,
              variantOverrides: _variantOverrides,
              skillOverrides: _skillOverrides,
              learnableSkills: _learnableFor,
              magic: draft.magic,
              magicOptions: t.magic.values.toList(),
              teamName: draft.teamName,
              icons: _icons,
              bloodlineRanks: _bloodlineRanks,
              onEditTeamName: (v) => setState(() {
                _teamNameOverride = v ?? '';
                _reencode();
              }),
              onChooseMagic: (v) => setState(() {
                _magicOverride = v ?? '';
                _reencode();
              }),
              onChooseVariant: (index, code) => setState(() {
                _variantOverrides[index] = code;
                _reencode();
              }),
              onSkillsChanged: (index, list) => setState(() {
                _skillOverrides[index] = list;
                _reencode();
              }),
              onOverrideBloodline: (index, letter) => setState(() {
                if (letter == null) {
                  _bloodlineOverrides.remove(index);
                } else {
                  _bloodlineOverrides[index] = letter;
                }
                _reencode();
              }),
              onCopy: _copy,
              tables: t,
              petOverrides: _petOverrides,
              natureOverrides: _natureOverrides,
              evOverrides: _evOverrides,
              onPetChanged: (index, id) => setState(() {
                _petOverrides[index] = id;
                // 换精灵要**清掉旧的形态与技能** —— 它们是"上一只精灵的"。
                // 不清的话会出码出一只不存在的搭配（用户在识别页踩过）。
                _variantOverrides.remove(index);
                _skillOverrides.remove(index);
                _reencode();
              }),
              onNatureChanged: (index, v) => setState(() {
                _natureOverrides[index] = v;
                _reencode();
              }),
              onEvsChanged: (index, v) => setState(() {
                _evOverrides[index] = v;
                _reencode();
              }),

              // ---- 四处文案：这里没有"识别"，也没有"识别失败" ----
              codeTitle: '阵容码',
              codeSubtitle: '复制后粘进游戏，在好友队伍那一栏导入',
              petsSectionTitle: '队伍配置',
              emptyCodeMessage: '选好精灵就会自动生成阵容码。',
              // 一进来当然还没有码 —— 那是正常状态，不是红色报错
              emptyCodeSeverity: NoticeSeverity.info,
              unresolvedBadge: '选择精灵',
              emptySlotLabel: '选择精灵',
              primaryActionLabel: '清空重来',
              onPrimaryAction: _clearAll,
              onCopyCode: _copy,
            ),
            const SizedBox(height: AppSpacing.lg),
            _BuilderNote(codeReady: draft.code.isNotEmpty),
          ],
        ],
      ),
    );
  }
}

/// 顶部提示：还差几只、下一步做什么。
class _BuilderHint extends StatelessWidget {
  const _BuilderHint({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = filled >= total;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_outline : Icons.person_add_alt,
          size: 16,
          color: done ? c.accent : c.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            done ? '已经选满 $total 只' : '点名字那一格选精灵 · 已选 $filled/$total',
            style: TextStyle(
              fontSize: AppType.sFootnote,
              color: c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 底部一句实话：码能出，但没选满不代表游戏里能用。
class _BuilderNote extends StatelessWidget {
  const _BuilderNote({required this.codeReady});

  final bool codeReady;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      codeReady
          ? '不足 6 只也能出码，但游戏里能不能导入要看官方规则 —— '
              '满编 6 只最稳。'
          : '技能、性格、个体资质、血脉都可以改；改完阵容码会自动重算。',
      style: TextStyle(
        fontSize: AppType.sCaption,
        color: c.textSecondary,
        height: 1.5,
      ),
    );
  }
}
