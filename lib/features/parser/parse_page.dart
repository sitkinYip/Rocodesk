/// 「阵容码解析」页：粘贴阵容码 -> 反查队伍。
///
/// ## 为什么和识别页共用 [ResultView]
///
/// 两条路径的**终点是同一个**：展示一支队伍、允许逐项手改、重新出码。
/// 区别只在起点（截图 vs 一段文本），所以没必要写第二套结果界面 ——
/// 那只会让"手改"这类功能要改两遍。
///
/// 差异通过 [toRecognizedTeam] 表达：解码出来的东西天然确定（无形态歧义、
/// 无 OCR 纠错候选），但阵容码里没有系别，所以那部分标签不显示。
///
/// ## 解析页比识别页多出来的东西
///
/// 识别页的输入是图片、来源不可编辑；这里输入**是一段文本**，
/// 所以粘贴后可以随时改。这一点让"解析 -> 微调 -> 出码"成为一个完整闭环。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/asset_loader.dart';
import '../../core/bloodline_ranks.dart';
import '../../core/codec_tables.dart';
import '../../core/icon_assets.dart';
import '../../core/models.dart';
import '../../core/pipeline.dart';
import '../../core/teamcodec.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';
import '../generator/result_view.dart';

class ParsePage extends StatefulWidget {
  const ParsePage({
    super.key,
    required this.icons,
    required this.bloodlineRanks,
    this.tables,
  });

  /// 参考图标与血脉排序由外层加载好后传进来，避免每页重复加载。
  final IconAssets icons;
  final BloodlineRanks bloodlineRanks;

  /// 直接注入数据表（测试用）。
  ///
  /// 不传时从**内置资产**读取 —— 刻意不用 `KnowledgeBase`：
  /// 那套要 `path_provider`（平台通道，测试里没有），而且它管的是
  /// "已下载的新数据优先"，解析只需要能解码。缓存坏掉不该连带解析一起废掉。
  final CodecTables? tables;

  @override
  State<ParsePage> createState() => _ParsePageState();
}

class _ParsePageState extends State<ParsePage> {
  final TextEditingController _input = TextEditingController();

  CodecTables? _tables;
  TeamCodec? _codec;
  String? _loadError;

  /// 解析成功的队伍（用于展示）。
  RecognizedTeam? _parsed;

  /// 解析失败的提示。与 [_parsed] 互斥。
  String? _parseError;

  /// 用户在本页改过的队伍名 / 魔法（覆盖解码结果）。
  String? _teamNameOverride;
  String? _magicOverride;

  /// 手改过的血脉，键是「第几只」（从 1 开始）。
  final Map<int, String> _bloodlineOverrides = {};

  /// 手改过的技能，键是「第几只」。
  final Map<int, List<String>> _skillOverrides = {};

  /// 手改过的精灵 / 性格 / 个体资质，键是「第几只」。
  final Map<int, String> _petOverrides = {};
  final Map<int, String> _natureOverrides = {};
  final Map<int, List<String>> _evOverrides = {};

  @override
  void initState() {
    super.initState();
    final injected = widget.tables;
    if (injected != null) {
      // 测试路径：直接用注入的表，不碰平台通道
      _tables = injected;
      _codec = TeamCodec(injected);
    } else {
      _loadTables();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    try {
      final tables = await loadCodecTablesFromAssets();
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _codec = TeamCodec(tables);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '资料表加载失败：$e');
    }
  }

  /// 解析输入框里的码。
  void _parse() {
    final codec = _codec;
    if (codec == null) return;

    // 用户从游戏里复制出来的码可能带换行/空格，先清掉再判空
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _parseError = '请先粘贴阵容码。';
        _parsed = null;
      });
      return;
    }

    try {
      final team = codec.decode(raw);
      if (!mounted) return;
      setState(() {
        _parsed = toRecognizedTeam(team, _tables!);
        _parseError = null;
        // 换了一串码就把上一条的手改清掉，否则会串到新码上
        _teamNameOverride = null;
        _magicOverride = null;
        _bloodlineOverrides.clear();
        _skillOverrides.clear();
      });
    } on TeamCodeException catch (e) {
      setState(() {
        _parseError = e.message;
        _parsed = null;
      });
    } catch (e) {
      setState(() {
        _parseError = '解析出错：$e';
        _parsed = null;
      });
    }
  }

  /// 用当前（可能已手改的）队伍重新出码。
  (String, String, String) _reencode() {
    final rt = _parsed;
    final codec = _codec;
    if (rt == null || codec == null) return ('', '', '');
    try {
      final team = toCodecTeam(
        rt,
        _bloodlineOverrides,
        skillOverrides: _skillOverrides,
        magicOverride: _magicOverride,
        teamNameOverride: _teamNameOverride,
        petOverrides: _petOverrides,
        natureOverrides: _natureOverrides,
        evOverrides: _evOverrides,
        tables: _tables,
      );
      return (codec.encode(team), '', codec.toGameText(team));
    } on TeamCodeException catch (e) {
      return ('', e.message, '');
    }
  }

  String get _effectiveTeamName {
    final o = _teamNameOverride;
    if (o != null && o.isNotEmpty) return o;
    final rt = _parsed;
    return (rt != null && rt.teamName.isNotEmpty) ? rt.teamName : '未命名队伍';
  }

  String get _effectiveMagic {
    final o = _magicOverride;
    if (o != null && o.isNotEmpty) return o;
    final rt = _parsed;
    return (rt != null && rt.magic.isNotEmpty) ? rt.magic : '进化之力';
  }

  Future<void> _copy(String text, String label) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label已复制'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阵容码解析')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: [
          if (_loadError != null) ...[
            InlineNotice(message: _loadError!, severity: NoticeSeverity.error),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ---------- 输入 ----------
          const SectionHeader(
            title: '粘贴阵容码',
            subtitle: '从游戏里复制出来的那串字符',
          ),
          AppGroup(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _input,
                  maxLines: 5,
                  minLines: 3,
                  style: AppType.code(context),
                  decoration: const InputDecoration(
                    hintText: 'B~xxxxxxxxx~...~ZZH~FA~',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    // 内容变了就把上一次的结果和错误都清掉 ——
                    // 留着旧结果会让人以为它对应新的码
                    if (_parsed != null || _parseError != null) {
                      setState(() {
                        _parsed = null;
                        _parseError = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        final t = data?.text?.trim() ?? '';
                        if (t.isEmpty) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('剪贴板里没有文本')),
                          );
                          return;
                        }
                        _input.text = t;
                        _parse();
                      },
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('从剪贴板粘贴'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        _input.clear();
                        setState(() {
                          _parsed = null;
                          _parseError = null;
                        });
                      },
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _codec == null ? null : _parse,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('解析'),
            ),
          ),

          // ---------- 错误 ----------
          if (_parseError != null) ...[
            const SizedBox(height: AppSpacing.lg),
            InlineNotice(message: _parseError!, severity: NoticeSeverity.error),
          ],

          // ---------- 结果 ----------
          if (_parsed != null) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: '解析结果',
              subtitle: '和识别一样，每一项都能点开改',
            ),
            Builder(builder: (context) {
              final (code, err, ai) = _reencode();
              return ResultView(
                team: _parsed!,
                code: code,
                codeError: err,
                aiText: ai,
                bloodlineOverrides: _bloodlineOverrides,
                variantOverrides: const {},
                skillOverrides: _skillOverrides,
                learnableSkills: (pet) {
                  final t = _tables;
                  if (t == null) return const [];
                  return t.skillMatcher.learnableNames(pet.petId);
                },
                magic: _effectiveMagic,
                magicOptions: _tables?.magic.values.toList() ?? const [],
                teamName: _effectiveTeamName,
                icons: widget.icons,
                bloodlineRanks: widget.bloodlineRanks,
                onChooseMagic: (m) => setState(() => _magicOverride = m),
                onEditTeamName: (n) => setState(() => _teamNameOverride = n),
                onChooseVariant: (_, _) {},
                onSkillsChanged: (i, list) =>
                    setState(() => _skillOverrides[i] = list),
                onOverrideBloodline: (i, letter) => setState(() {
                  if (letter == null) {
                    _bloodlineOverrides.remove(i);
                  } else {
                    _bloodlineOverrides[i] = letter;
                  }
                }),
                onCopy: _copy,
                // 解析页：码是**输入**，所以：
                //   * 不给「重新识别」—— 这个页面没有识别这一步
                //   * 但**要给「复制」**—— 改过之后的结果需要能复制走
                //     （这一点我一开始判断错了，以为"他本来就有码"，
                //      实际上改完之后那串新码才是他要的）
                codeTitle: '修改后的阵容码',
                codeSubtitle: '改了上面的内容，这串码会跟着更新',
                onCopyCode: _copy,
                onPrimaryAction: null,
                // ---- 整队可编辑 ----
                // 解析页同样全开放：拿到一串码之后也能自己重新搭配
                tables: _tables,
                petOverrides: _petOverrides,
                natureOverrides: _natureOverrides,
                evOverrides: _evOverrides,
                onPetChanged: (i, id) => setState(() => _petOverrides[i] = id),
                onNatureChanged: (i, n) =>
                    setState(() => _natureOverrides[i] = n),
                onEvsChanged: (i, e) => setState(() => _evOverrides[i] = e),
              );
            }),
          ],

          // ---------- 空态 ----------
          if (_parsed == null && _parseError == null && _loadError == null) ...[
            const SizedBox(height: AppSpacing.xxl),
            const EmptyState(
              icon: Icons.qr_code_2_outlined,
              title: '还没有解析结果',
              description: '把游戏里的阵容码粘贴到上面，点「解析」就能反查出\n'
                  '这 6 只精灵、它们的性格、个体资质、技能与血脉。\n\n'
                  '解析出来的内容也可以直接改 —— 改完会重新生成一串码。',
            ),
          ],
        ],
      ),
    );
  }
}
