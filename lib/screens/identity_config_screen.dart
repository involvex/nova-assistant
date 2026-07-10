import 'package:flutter/material.dart';
import 'package:nova_assistant/models/agent_identity.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';

class IdentityConfigScreen extends StatefulWidget {
  const IdentityConfigScreen({super.key});

  @override
  State<IdentityConfigScreen> createState() => _IdentityConfigScreenState();
}

class _IdentityConfigScreenState extends State<IdentityConfigScreen> {
  late TextEditingController _nameController;
  late TextEditingController _backstoryController;
  String? _avatarEmoji;
  Set<AgentSkill> _selectedSkills = {AgentSkill.general};
  Set<KnowledgeSource> _selectedSources = {KnowledgeSource.none};
  bool _isLoading = true;

  static const List<String> _emojiOptions = [
    '🤖',
    '🦊',
    '🦉',
    '🐱',
    '🐶',
    '🦋',
    '🌟',
    '💡',
    '🎯',
    '🚀',
    '🔮',
    '🧙',
    '🦄',
    '🐉',
    '🦅',
    '🦁',
    '🐼',
    '🦊',
    '🐨',
    '🦁',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Nova');
    _backstoryController = TextEditingController();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    final identity = await IdentityService.getIdentity();
    if (mounted) {
      setState(() {
        _nameController.text = identity.name;
        _backstoryController.text = identity.backstory;
        _avatarEmoji = identity.avatarEmoji;
        _selectedSkills =
            identity.skills.isNotEmpty ? identity.skills : {AgentSkill.general};
        _selectedSources = identity.sources.isNotEmpty
            ? identity.sources
            : {KnowledgeSource.none};
        _isLoading = false;
      });
    }
  }

  Future<void> _saveIdentity() async {
    final identity = AgentIdentity(
      name: _nameController.text.trim().isEmpty
          ? 'Nova'
          : _nameController.text.trim(),
      avatarEmoji: _avatarEmoji,
      backstory: _backstoryController.text.trim(),
      skills: _selectedSkills,
      sources: _selectedSources,
      isActive: true,
    );
    await IdentityService.saveIdentity(identity);
    await ModelOrchestrator.refreshSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identity saved'),
          backgroundColor: Color(0xFF6C63FF),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _backstoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Agent Identity'),
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveIdentity,
            child: const Text(
              'Save',
              style: TextStyle(color: Color(0xFF6C63FF)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPreviewCard(),
                const SizedBox(height: 24),
                _buildNameSection(),
                const SizedBox(height: 16),
                _buildEmojiSelector(),
                const SizedBox(height: 16),
                _buildBackstorySection(),
                const SizedBox(height: 24),
                _buildSkillsSection(),
                const SizedBox(height: 24),
                _buildSourcesSection(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _avatarEmoji ?? '🤖',
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.isEmpty ? 'Nova' : _nameController.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_selectedSkills.length} skills • ${_selectedSources.length} sources',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameSection() {
    return _sectionTitle('Name');
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildEmojiSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Avatar'),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: _emojiOptions.length,
            itemBuilder: (context, index) {
              final emoji = _emojiOptions[index];
              final isSelected = emoji == _avatarEmoji;
              return GestureDetector(
                onTap: () => setState(() => _avatarEmoji = emoji),
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6C63FF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? null
                        : Border.all(color: Colors.grey[700]!),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBackstorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Backstory (Optional)'),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _backstoryController,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            decoration: InputDecoration(
              hintText:
                  'e.g., "I am a coding assistant created to help developers..."',
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkillsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Skills'),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: AgentSkill.values.map((skill) {
              final isSelected = _selectedSkills.contains(skill);
              return CheckboxListTile(
                value: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedSkills = {..._selectedSkills, skill};
                    } else {
                      if (_selectedSkills.length > 1) {
                        _selectedSkills =
                            _selectedSkills.where((s) => s != skill).toSet();
                      }
                    }
                  });
                },
                title: Text(
                  skill.displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[400],
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  skill.description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                activeColor: const Color(0xFF6C63FF),
                checkColor: Colors.white,
                dense: true,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Knowledge Sources'),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: KnowledgeSource.values.map((source) {
              final isSelected = _selectedSources.contains(source);
              return CheckboxListTile(
                value: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      if (source == KnowledgeSource.none) {
                        _selectedSources = {source};
                      } else {
                        _selectedSources = {
                          ..._selectedSources.where(
                            (s) => s != KnowledgeSource.none,
                          ),
                          source,
                        };
                      }
                    } else {
                      if (_selectedSources.length > 1) {
                        _selectedSources =
                            _selectedSources.where((s) => s != source).toSet();
                      }
                    }
                  });
                },
                title: Text(
                  source.displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[400],
                    fontWeight:
                        isSelected ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  source.description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                activeColor: const Color(0xFF6C63FF),
                checkColor: Colors.white,
                dense: true,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
