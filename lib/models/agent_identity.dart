import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum AgentSkill {
  general('General Assistant', 'Provides helpful responses across topics'),
  coding('Coding', 'Writes, reviews, and explains code in multiple languages'),
  imageAnalysis('Image Analysis', 'Understands and describes images'),
  research('Research', 'Searches and synthesizes information from sources'),
  creative('Creative Writing', 'Helps with creative writing and brainstorming'),
  tutoring('Tutoring', 'Explains concepts and helps with learning'),
  analysis('Data Analysis', 'Analyzes data and provides insights'),
  planning('Planning', 'Helps with project planning and organization');

  final String displayName;
  final String description;

  const AgentSkill(this.displayName, this.description);
}

enum KnowledgeSource {
  none('No external sources', 'Relies only on training knowledge'),
  webSearch('Web Search', 'Can search the internet for current information'),
  documentation('Documentation', 'Has access to documentation and manuals'),
  codeBase('Codebase', 'Knows about a specific codebase or repository'),
  knowledgeBase('Knowledge Base', 'Has access to a custom knowledge base');

  final String displayName;
  final String description;

  const KnowledgeSource(this.displayName, this.description);
}

class AgentIdentity {
  final String name;
  final String? avatarEmoji;
  final String backstory;
  final Set<AgentSkill> skills;
  final Set<KnowledgeSource> sources;
  final bool isActive;

  const AgentIdentity({
    this.name = 'Nova',
    this.avatarEmoji,
    this.backstory = '',
    this.skills = const {AgentSkill.general},
    this.sources = const {KnowledgeSource.none},
    this.isActive = false,
  });

  AgentIdentity copyWith({
    String? name,
    String? avatarEmoji,
    String? backstory,
    Set<AgentSkill>? skills,
    Set<KnowledgeSource>? sources,
    bool? isActive,
  }) {
    return AgentIdentity(
      name: name ?? this.name,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      backstory: backstory ?? this.backstory,
      skills: skills ?? this.skills,
      sources: sources ?? this.sources,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatarEmoji': avatarEmoji,
    'backstory': backstory,
    'skills': skills.map((s) => s.name).toList(),
    'sources': sources.map((s) => s.name).toList(),
    'isActive': isActive,
  };

  factory AgentIdentity.fromJson(Map<String, dynamic> json) => AgentIdentity(
    name: json['name'] as String? ?? 'Nova',
    avatarEmoji: json['avatarEmoji'] as String?,
    backstory: json['backstory'] as String? ?? '',
    skills:
        (json['skills'] as List<dynamic>?)
            ?.map(
              (s) => AgentSkill.values.firstWhere(
                (e) => e.name == s,
                orElse: () => AgentSkill.general,
              ),
            )
            .toSet() ??
        {AgentSkill.general},
    sources:
        (json['sources'] as List<dynamic>?)
            ?.map(
              (s) => KnowledgeSource.values.firstWhere(
                (e) => e.name == s,
                orElse: () => KnowledgeSource.none,
              ),
            )
            .toSet() ??
        {KnowledgeSource.none},
    isActive: json['isActive'] as bool? ?? false,
  );

  String buildSystemPrompt() {
    final buffer = StringBuffer();

    buffer.write('You are $name');
    if (avatarEmoji != null) {
      buffer.write(' $avatarEmoji');
    }
    buffer.write(', an AI assistant.');

    if (backstory.isNotEmpty) {
      buffer.write('\n\nBackground: $backstory');
    }

    if (skills.isNotEmpty) {
      buffer.write('\n\nYour skills include:');
      for (final skill in skills) {
        buffer.write('\n- ${skill.displayName}: ${skill.description}');
      }
    }

    if (sources.isNotEmpty && !sources.contains(KnowledgeSource.none)) {
      buffer.write('\n\nYou have access to:');
      for (final source in sources) {
        if (source != KnowledgeSource.none) {
          buffer.write('\n- ${source.displayName}: ${source.description}');
        }
      }
    }

    buffer.write(
      '\n\nYou run entirely on the device — no data is sent to external servers.',
    );
    buffer.write(' Be helpful, concise, and friendly.');
    buffer.write(
      '\n\nAvailable tools: get_time, set_alarm, cancel_alarm, open_app, '
      'search_web, get_weather, send_sms, open_settings, take_screenshot, '
      'create_task, list_tasks, complete_task, create_note, search_notes, list_notes.',
    );
    buffer.write(
      '\nTool use: When the user request is actionable with a tool and the '
      'needed details are already in the message, call the tool immediately. '
      'For alarms, convert AM/PM to 24-hour (7 PM → hour=19) and use minute=0 '
      'when minutes are omitted.',
    );

    return buffer.toString();
  }

  /// Single-line variant of [buildSystemPrompt] used on tight Android Gemma 4
  /// sessions. The detailed persona is reserved for non-Android / desktop /
  /// high-context runs via [buildSystemPrompt].
  String buildCompactSystemPrompt() {
    final buffer = StringBuffer('You are $name');
    if (avatarEmoji != null) {
      buffer.write(' $avatarEmoji');
    }
    buffer.write('. Be concise and helpful.');

    return buffer.toString();
  }
}

class IdentityService {
  static const _key = 'agent_identity';
  static const _activeKey = 'identity_is_active';
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<AgentIdentity> getIdentity() async {
    final prefs = await _p;
    final json = prefs.getString(_key);
    if (json == null) return const AgentIdentity();
    try {
      return AgentIdentity.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return const AgentIdentity();
    }
  }

  static Future<void> saveIdentity(AgentIdentity identity) async {
    final prefs = await _p;
    await prefs.setString(_key, jsonEncode(identity.toJson()));
  }

  static Future<bool> isActive() async {
    final prefs = await _p;

    return prefs.getBool(_activeKey) ?? false;
  }

  static Future<void> setActive(bool active) async {
    final prefs = await _p;
    await prefs.setBool(_activeKey, active);
  }

  static Future<void> clear() async {
    final prefs = await _p;
    await prefs.remove(_key);
    await prefs.remove(_activeKey);
  }
}
