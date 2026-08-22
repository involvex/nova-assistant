import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nova_assistant/models/adult_mode_policy.dart';
import 'package:nova_assistant/models/diffusion_model_info.dart';
import 'package:nova_assistant/screens/settings_screen.dart';
import 'package:nova_assistant/services/image_generation_service.dart';

typedef ImageGenerationResult = ({String prompt, Uint8List bytes});

Future<ImageGenerationResult?> showImageGenerationSheet(BuildContext context) {
  return showModalBottomSheet<ImageGenerationResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ImageGenerationSheet(),
  );
}

class ImageGenerationSheet extends StatefulWidget {
  const ImageGenerationSheet({super.key});

  @override
  State<ImageGenerationSheet> createState() => _ImageGenerationSheetState();
}

class _ImageGenerationSheetState extends State<ImageGenerationSheet> {
  static const _surfaceColor = Color(0xFF1A1A2E);
  static const _accentColor = Color(0xFF6C63FF);

  final TextEditingController _promptController = TextEditingController();
  StreamSubscription<GenProgress>? _progressSub;

  bool _checkingModel = true;
  bool _modelInstalled = false;
  bool _generating = false;
  double _progress = 0;
  int _selectedSize = 512;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_checkModelInstalled());
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _checkModelInstalled() async {
    final installed = await ImageGenerationService.instance.isModelInstalled();
    if (!mounted) return;
    setState(() {
      _modelInstalled = installed;
      _checkingModel = false;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    unawaited(_checkModelInstalled());
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Enter a description first');

      return;
    }
    if (_generating) return;

    setState(() {
      _generating = true;
      _progress = 0;
      _error = null;
    });

    final adultModeEnabled = await AdultModePolicy.isEnabled();
    if (!mounted) return;

    if (!adultModeEnabled && !AdultModePolicy.isPromptSafe(prompt)) {
      setState(() {
        _generating = false;
        _error =
            'Blocked by the safety filter. Enable Adult Mode in Settings '
            'to allow this prompt.';
      });

      return;
    }

    if (ImageGenerationService.instance.isGenerating) {
      setState(() {
        _generating = false;
        _error = 'An image is already being generated';
      });

      return;
    }

    _progressSub?.cancel();
    _progressSub = ImageGenerationService.instance.progressStream.listen((
      event,
    ) {
      if (!mounted) return;
      setState(() => _progress = (event.percent / 100).clamp(0.0, 1.0));
    });

    final size = ImageSize.values.firstWhere(
      (s) => s.pixels == _selectedSize,
      orElse: () => ImageSize.size512,
    );

    final bytes = await ImageGenerationService.instance.generateImage(
      prompt,
      size: size,
    );

    if (!mounted) return;

    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _generating = false;
        _error =
            'Generation failed. Check that a diffusion model is installed '
            'and try again.';
      });
      return;
    }

    Navigator.of(context).pop((prompt: prompt, bytes: bytes));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    Widget content;
    if (_checkingModel) {
      content = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    } else if (!_modelInstalled) {
      content = _buildNoModelBody();
    } else {
      content = _buildFormBody();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: _accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _modelInstalled || _checkingModel
                    ? 'Generate image'
                    : 'No diffusion model',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white54),
              tooltip: 'Close',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(child: SingleChildScrollView(child: content)),
      ],
    );
  }

  Widget _buildNoModelBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Z-Image-Turbo or FLUX.2-klein must be installed before images can '
          'be generated on-device.',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _openSettings,
          style: FilledButton.styleFrom(backgroundColor: _accentColor),
          icon: const Icon(Icons.download_outlined, size: 20),
          label: const Text('Open Settings to install'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFormBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _promptController,
          enabled: !_generating,
          maxLines: 3,
          minLines: 2,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Describe the image to generate...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
          onSubmitted: (_) => unawaited(_generate()),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Size',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(width: 10),
            ...ImageSize.values.map(_buildSizeChip),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_generating) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(value: _progress, color: _accentColor),
          const SizedBox(height: 6),
          Text(
            'Running diffusion on-device — this can take a while...',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _generating ? null : () => unawaited(_generate()),
          style: FilledButton.styleFrom(backgroundColor: _accentColor),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(_generating ? 'Generating...' : 'Generate'),
        ),
      ],
    );
  }

  Widget _buildSizeChip(ImageSize size) {
    final selected = _selectedSize == size.pixels;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(size.label),
        selected: selected,
        onSelected: _generating
            ? null
            : (_) => setState(() => _selectedSize = size.pixels),
        selectedColor: _accentColor,
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
        showCheckmark: false,
      ),
    );
  }
}
