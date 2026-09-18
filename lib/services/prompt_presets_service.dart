import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:nova_assistant/models/prompt_preset.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/utils/suggestion_json_parser.dart';

/// Context used to rank / generate empty-chat starter chips.
class PromptStarterContext {
  final String? roleName;
  final int hourOfDay;
  final bool hasImageGen;
  final String? recentTopic;

  const PromptStarterContext({
    this.roleName,
    this.hourOfDay = 12,
    this.hasImageGen = false,
    this.recentTopic,
  });
}

class PromptPresetsService {
  static PromptPresetsService? _instance;
  static PromptPresetsService get instance =>
      _instance ??= PromptPresetsService._();
  PromptPresetsService._();

  static const _prefsKey = 'nova_prompt_presets';
  static const _uuid = Uuid();

  StreamController<List<PromptPreset>> _presetsController =
      StreamController<List<PromptPreset>>.broadcast();
  Stream<List<PromptPreset>> get presetsStream => _presetsController.stream;

  List<PromptPreset> _presets = [];

  List<PromptPreset> get presets => List.unmodifiable(_presets);

  Future<void> initialize() async {
    if (_presetsController.isClosed) {
      _presetsController = StreamController<List<PromptPreset>>.broadcast();
    }
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _presets = list
            .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _presets = _defaultPresets();
      }
    } else {
      _presets = _defaultPresets();
    }
    await _save();
    _notifyListeners();
  }

  Future<PromptPreset> createPreset({
    required String name,
    required String prompt,
    String? description,
    String? category,
  }) async {
    final preset = PromptPreset(
      id: _uuid.v4(),
      name: name,
      prompt: prompt,
      description: description,
      category: category,
    );
    _presets.insert(0, preset);
    await _save();
    _notifyListeners();
    return preset;
  }

  Future<void> updatePreset(PromptPreset preset) async {
    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index != -1) {
      _presets[index] = preset;
      await _save();
      _notifyListeners();
    }
  }

  Future<void> deletePreset(String presetId) async {
    _presets.removeWhere((p) => p.id == presetId);
    await _save();
    _notifyListeners();
  }

  Future<void> incrementUseCount(String presetId) async {
    final index = _presets.indexWhere((p) => p.id == presetId);
    if (index != -1) {
      _presets[index] = _presets[index].copyWith(
        useCount: _presets[index].useCount + 1,
      );
      await _save();
      _notifyListeners();
    }
  }

  List<PromptPreset> searchPresets(String query) {
    final lower = query.toLowerCase();
    return _presets.where((p) {
      return p.name.toLowerCase().contains(lower) ||
          p.prompt.toLowerCase().contains(lower) ||
          (p.description?.toLowerCase().contains(lower) ?? false) ||
          (p.category?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  List<PromptPreset> getPresetsByCategory(String category) =>
      _presets.where((p) => p.category == category).toList();

  Set<String> get allCategories {
    final categories = <String>{};
    for (final preset in _presets) {
      if (preset.category != null) {
        categories.add(preset.category!);
      }
    }
    return categories;
  }

  List<PromptPreset> getMostUsedPresets() {
    final sorted = List<PromptPreset>.from(_presets);
    sorted.sort((a, b) => b.useCount.compareTo(a.useCount));
    return sorted.take(5).toList();
  }

  /// Short starter chips for an empty chat (Summarize / Plan / Debug / Learn).
  List<({String label, String prompt})> get emptyStateStarters =>
      contextualEmptyStateStarters(const PromptStarterContext());

  /// Heuristic starters ranked by role, time of day, and capabilities.
  List<({String label, String prompt})> contextualEmptyStateStarters(
    PromptStarterContext context,
  ) {
    final ranked = _rankedStarterNames(context);
    final byName = <String, PromptPreset>{for (final p in _presets) p.name: p};
    final starters = <({String label, String prompt})>[];
    for (final name in ranked) {
      final preset = byName[name];
      if (preset != null) {
        starters.add((label: name, prompt: preset.prompt));
      } else {
        final fallback = _starterFallback(name);
        if (fallback != null) starters.add(fallback);
      }
      if (starters.length >= 4) break;
    }

    return starters;
  }

  /// Instant heuristics, then optionally refresh via LLM when a backend is ready.
  Future<List<({String label, String prompt})>> resolveEmptyStateStarters(
    PromptStarterContext context, {
    bool preferLlm = true,
  }) async {
    final fallback = contextualEmptyStateStarters(context);
    if (!preferLlm) return fallback;

    final generated = await _generateStartersWithLlm(context);
    if (generated.isEmpty) return fallback;

    return generated;
  }

  /// Ask the model for reusable prompt presets about [topic], then save them.
  Future<List<PromptPreset>> generateAndSavePresets({
    required String topic,
    String? roleName,
  }) async {
    final drafts = await generatePresetDrafts(topic: topic, roleName: roleName);
    final created = <PromptPreset>[];
    for (final draft in drafts) {
      created.add(
        await createPreset(
          name: draft.name,
          prompt: draft.prompt,
          description: draft.description,
          category: draft.category ?? 'Generated',
        ),
      );
    }

    return created;
  }

  /// LLM drafts only (does not persist). Empty list on failure.
  Future<
    List<({String name, String prompt, String? description, String? category})>
  >
  generatePresetDrafts({required String topic, String? roleName}) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty) return const [];

    final role = roleName ?? ModelOrchestrator.instance.assistantRole.name;
    final prompt =
        'Generate 4 reusable prompt presets for an on-device AI assistant.\n'
        'Assistant role: $role\n'
        'Topic or goal: $trimmed\n'
        'Return ONLY a JSON array of objects with keys: '
        'name (short), prompt (ready-to-use template, may end with colon or '
        'newline for user input), description (one sentence), category '
        '(Coding|Writing|Productivity|Learning|Creative|Generated).\n'
        'Make prompts actionable and specific to the topic.';

    final raw = await ModelOrchestrator.instance.completeOnce(prompt: prompt);
    if (raw == null || raw.isEmpty) return const [];

    return SuggestionJsonParser.parsePresetDrafts(raw, max: 5);
  }

  Future<List<({String label, String prompt})>> _generateStartersWithLlm(
    PromptStarterContext context,
  ) async {
    final role =
        context.roleName ?? ModelOrchestrator.instance.assistantRole.name;
    final hour = context.hourOfDay;
    final timeHint = hour < 12
        ? 'morning'
        : hour < 17
        ? 'afternoon'
        : 'evening';
    final extras = <String>[
      if (context.hasImageGen) 'image generation is available',
      if (context.recentTopic != null && context.recentTopic!.isNotEmpty)
        'recent interest: ${context.recentTopic}',
    ].join('; ');

    final prompt =
        'Suggest 4 short chat starter chips for an empty conversation.\n'
        'Assistant role: $role\n'
        'Time of day: $timeHint\n'
        '${extras.isEmpty ? '' : 'Context: $extras\n'}'
        'Return ONLY a JSON array of objects: '
        '{"label":"max 18 chars","prompt":"full prompt to put in the composer"}.\n'
        'Labels must be distinct. Prompts should invite the user to continue '
        '(often end with a colon or blank for them to fill in).';

    try {
      final raw = await ModelOrchestrator.instance.completeOnce(prompt: prompt);
      if (raw == null || raw.isEmpty) return const [];
      final parsed = SuggestionJsonParser.parseLabeledPrompts(raw, max: 4);
      if (parsed.length < 2) return const [];

      return parsed;
    } catch (e) {
      debugPrint('PromptPresetsService LLM starters failed: $e');

      return const [];
    }
  }

  List<String> _rankedStarterNames(PromptStarterContext context) {
    final role = (context.roleName ?? '').toLowerCase();
    final hour = context.hourOfDay;
    final names = <String>[];

    if (role.contains('coder') || role.contains('code')) {
      names.addAll(['Debug', 'Explain Code', 'Write Unit Test', 'Plan']);
    } else if (role.contains('creative')) {
      names.addAll([
        'Brainstorm Ideas',
        'Improve Writing',
        'Learn',
        'Summarize',
      ]);
    } else if (role.contains('student')) {
      names.addAll(['Learn', 'Summarize', 'Plan', 'Explain Code']);
    } else if (role.contains('analyst')) {
      names.addAll(['Summarize', 'Plan', 'Debug', 'Learn']);
    } else {
      names.addAll(['Summarize', 'Plan', 'Debug', 'Learn']);
    }

    if (hour >= 5 && hour < 10) {
      names.insert(0, 'Plan');
    } else if (hour >= 21 || hour < 5) {
      names.insert(0, 'Summarize');
    }

    if (context.hasImageGen) {
      names.insert(0, 'Generate Image');
    }

    // Deduplicate preserving order
    final seen = <String>{};
    final ordered = <String>[];
    for (final name in names) {
      if (seen.add(name)) ordered.add(name);
    }

    return ordered;
  }

  static ({String label, String prompt})? _starterFallback(String name) {
    return switch (name) {
      'Summarize' => (
        label: 'Summarize',
        prompt:
            'Provide a concise summary of the following text, '
            'highlighting the key points:\n\n',
      ),
      'Plan' => (
        label: 'Plan',
        prompt:
            'Help me build a clear step-by-step plan for the following '
            'goal:\n\n',
      ),
      'Debug' => (
        label: 'Debug',
        prompt:
            'I encountered the following error. Help me debug it '
            'step by step:\n\n',
      ),
      'Learn' => (
        label: 'Learn',
        prompt:
            'Teach me about the following topic like a patient tutor. '
            'Use simple explanations and a short quiz at the end:\n\n',
      ),
      'Explain Code' => (
        label: 'Explain Code',
        prompt:
            'Explain the following code in detail, including what each '
            'part does and why it works:\n\n',
      ),
      'Write Unit Test' => (
        label: 'Unit Test',
        prompt:
            'Write comprehensive unit tests for the following code, '
            'covering edge cases and error scenarios:\n\n',
      ),
      'Improve Writing' => (
        label: 'Improve Writing',
        prompt:
            'Improve the following text for clarity, grammar, and style '
            'while maintaining the original meaning:\n\n',
      ),
      'Brainstorm Ideas' => (
        label: 'Brainstorm',
        prompt:
            'Help me brainstorm creative ideas for the following topic '
            'or problem:\n\n',
      ),
      'Generate Image' => (
        label: 'Generate Image',
        prompt: 'Generate an image of: ',
      ),
      _ => null,
    };
  }

  List<PromptPreset> _defaultPresets() {
    return [
      PromptPreset(
        id: _uuid.v4(),
        name: 'Explain Code',
        prompt:
            'Explain the following code in detail, including what each '
            'part does and why it works:',
        description: 'Get a detailed explanation of code snippets',
        category: 'Coding',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Debug',
        prompt:
            'I encountered the following error. Help me debug it '
            'step by step:\n\n',
        description: 'Get help debugging errors',
        category: 'Coding',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Write Unit Test',
        prompt:
            'Write comprehensive unit tests for the following code, '
            'covering edge cases and error scenarios:',
        description: 'Generate unit tests for code',
        category: 'Coding',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Summarize',
        prompt:
            'Provide a concise summary of the following text, '
            'highlighting the key points:\n\n',
        description: 'Summarize text or content',
        category: 'Writing',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Plan',
        prompt:
            'Help me build a clear step-by-step plan for the following '
            'goal:\n\n',
        description: 'Break a goal into actionable steps',
        category: 'Productivity',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Learn',
        prompt:
            'Teach me about the following topic like a patient tutor. '
            'Use simple explanations and a short quiz at the end:\n\n',
        description: 'Learn a topic with a short quiz',
        category: 'Learning',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Improve Writing',
        prompt:
            'Improve the following text for clarity, grammar, and style '
            'while maintaining the original meaning:',
        description: 'Improve text quality',
        category: 'Writing',
      ),
      PromptPreset(
        id: _uuid.v4(),
        name: 'Brainstorm Ideas',
        prompt:
            'Help me brainstorm creative ideas for the following topic '
            'or problem:',
        description: 'Generate creative ideas',
        category: 'Creative',
      ),
    ];
  }

  Future<void> replaceAll(List<PromptPreset> presets) async {
    _presets = List<PromptPreset>.from(presets);
    await _save();
    _notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_presets.map((p) => p.toJson()).toList());
    await prefs.setString(_prefsKey, json);
  }

  void _notifyListeners() {
    _presetsController.add(presets);
  }

  Future<void> dispose() async {
    await _presetsController.close();
  }

  static void reset() {
    _instance = null;
  }
}
