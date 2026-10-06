/// 应用设置（主题模式、模型服务商、API Key、模型名）。
///
/// 架构决定：**纯前端填 Key，存本地**，不经过任何自建后端。
/// 好处是能公开分发、不承担费用与滥用风险；代价是每个用户要自己申请 Key。
///
/// 安全说明（必须如实告知用户）：
///   * Key 存在平台本地存储里（Web 是 localStorage / 桌面与移动是各平台的偏好存储）；
///   * 它**没有加密**，同一台设备上的其他程序理论上可读；
///   * 因此**不建议在公用设备上填 Key**，也不要用主账号的长期 Key。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支持的模型服务商。都是 OpenAI 兼容协议，换 baseUrl + model 即可。
enum ModelProvider {
  dashscope('阿里云百炼', 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'qwen3.5-omni-plus-2026-03-15'),
  openai('OpenAI', 'https://api.openai.com/v1', 'gpt-4o'),
  zhipu('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4v-plus'),
  siliconflow('硅基流动', 'https://api.siliconflow.cn/v1',
      'Qwen/Qwen2.5-VL-72B-instruct'),
  moonshot('月之暗面 Kimi', 'https://api.moonshot.cn/v1',
      'moonshot-v1-8k-vision-preview'),
  custom('自定义（OpenAI 兼容）', '', '');

  const ModelProvider(this.label, this.baseUrl, this.defaultModel);

  final String label;
  final String baseUrl;
  final String defaultModel;

  static ModelProvider fromName(String? name) => ModelProvider.values.firstWhere(
        (p) => p.name == name,
        orElse: () => ModelProvider.dashscope,
      );
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.provider = ModelProvider.dashscope,
    this.apiKey = '',
    this.modelOverride = '',
    this.baseUrlOverride = '',
    this.autoAnalyze = true,
    this.checkKnowledgeUpdates = true,
    this.knowledgeUrl = '',
  });

  final ThemeMode themeMode;
  final ModelProvider provider;
  final String apiKey;

  /// 留空则用服务商的默认模型。
  final String modelOverride;
  final String baseUrlOverride;

  /// 选完图后自动开始识别。
  final bool autoAnalyze;

  /// 启动时是否检查知识库更新。
  ///
  /// 默认开。关掉的意义：流量敏感、或者明确想固定用内置数据。
  /// 注意**关掉不影响功能** —— 内置数据永远可用。
  final bool checkKnowledgeUpdates;

  /// 远程知识库 manifest 的地址。
  ///
  /// 留空 = 不检查更新（默认）。它就是个**静态 JSON 文件**的地址，
  /// 不需要任何后端服务。
  final String knowledgeUrl;

  String get effectiveModel =>
      modelOverride.trim().isNotEmpty ? modelOverride.trim() : provider.defaultModel;

  String get effectiveBaseUrl => baseUrlOverride.trim().isNotEmpty
      ? baseUrlOverride.trim()
      : provider.baseUrl;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 是否具备调用模型的条件（自定义服务商必须自己填 baseUrl）。
  bool get isReady =>
      hasApiKey && effectiveBaseUrl.isNotEmpty && effectiveModel.isNotEmpty;

  /// 是否需要并且能够检查知识库更新。
  bool get canCheckKnowledge =>
      checkKnowledgeUpdates && knowledgeUrl.trim().isNotEmpty;

  AppSettings copyWith({
    ThemeMode? themeMode,
    ModelProvider? provider,
    String? apiKey,
    String? modelOverride,
    String? baseUrlOverride,
    bool? autoAnalyze,
    bool? checkKnowledgeUpdates,
    String? knowledgeUrl,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        modelOverride: modelOverride ?? this.modelOverride,
        baseUrlOverride: baseUrlOverride ?? this.baseUrlOverride,
        autoAnalyze: autoAnalyze ?? this.autoAnalyze,
        checkKnowledgeUpdates: checkKnowledgeUpdates ?? this.checkKnowledgeUpdates,
        knowledgeUrl: knowledgeUrl ?? this.knowledgeUrl,
      );
}

/// 设置的读写与内存态。用 [ChangeNotifier] 让 UI 跟随。
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs, this._settings);

  static const _kThemeMode = 'theme_mode';
  static const _kProvider = 'provider';
  static const _kApiKey = 'api_key';
  static const _kModel = 'model_override';
  static const _kBaseUrl = 'base_url_override';
  static const _kAutoAnalyze = 'auto_analyze';
  static const _kCheckKb = 'check_kb_updates';
  static const _kKbUrl = 'kb_url';

  final SharedPreferences _prefs;
  AppSettings _settings;

  AppSettings get settings => _settings;
  ThemeMode get themeMode => _settings.themeMode;
  ModelProvider get provider => _settings.provider;
  String get apiKey => _settings.apiKey;
  bool get isReady => _settings.isReady;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStore._(
      prefs,
      AppSettings(
        themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
        provider: ModelProvider.fromName(prefs.getString(_kProvider)),
        apiKey: prefs.getString(_kApiKey) ?? '',
        modelOverride: prefs.getString(_kModel) ?? '',
        baseUrlOverride: prefs.getString(_kBaseUrl) ?? '',
        autoAnalyze: prefs.getBool(_kAutoAnalyze) ?? true,
        checkKnowledgeUpdates: prefs.getBool(_kCheckKb) ?? true,
        knowledgeUrl: prefs.getString(_kKbUrl) ?? '',
      ),
    );
  }

  /// 供测试使用的内存实现，不触碰平台通道。
  static SettingsStore inMemory({AppSettings settings = const AppSettings()}) =>
      SettingsStore._(_MemoryPrefs(), settings);

  static ThemeMode _parseThemeMode(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _themeModeName(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> _persist(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _prefs.setString(_kThemeMode, _themeModeName(next.themeMode));
    await _prefs.setString(_kProvider, next.provider.name);
    await _prefs.setString(_kApiKey, next.apiKey);
    await _prefs.setString(_kModel, next.modelOverride);
    await _prefs.setString(_kBaseUrl, next.baseUrlOverride);
    await _prefs.setBool(_kAutoAnalyze, next.autoAnalyze);
    await _prefs.setBool(_kCheckKb, next.checkKnowledgeUpdates);
    await _prefs.setString(_kKbUrl, next.knowledgeUrl);
  }

  Future<void> setThemeMode(ThemeMode m) =>
      _persist(_settings.copyWith(themeMode: m));

  Future<void> setProvider(ModelProvider p) =>
      _persist(_settings.copyWith(provider: p));

  Future<void> setApiKey(String v) =>
      _persist(_settings.copyWith(apiKey: v.trim()));

  Future<void> setModelOverride(String v) =>
      _persist(_settings.copyWith(modelOverride: v.trim()));

  Future<void> setBaseUrlOverride(String v) =>
      _persist(_settings.copyWith(baseUrlOverride: v.trim()));

  Future<void> setAutoAnalyze(bool v) =>
      _persist(_settings.copyWith(autoAnalyze: v));

  Future<void> setCheckKnowledgeUpdates(bool v) =>
      _persist(_settings.copyWith(checkKnowledgeUpdates: v));

  Future<void> setKnowledgeUrl(String v) =>
      _persist(_settings.copyWith(knowledgeUrl: v.trim()));

  /// 清除本机保存的 Key（用户换机器或怀疑泄露时用）。
  Future<void> clearApiKey() => _persist(_settings.copyWith(apiKey: ''));
}

/// 测试用的假 SharedPreferences。
class _MemoryPrefs implements SharedPreferences {
  final Map<String, Object> _m = {};

  @override
  Object? get(String key) => _m[key];

  @override
  String? getString(String key) => _m[key] as String?;

  @override
  bool? getBool(String key) => _m[key] as bool?;

  @override
  Future<bool> setString(String key, String value) async {
    _m[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _m[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试用实现只支持 String/Bool 读写');

  @override
  String toString() => jsonEncode(_m);
}
