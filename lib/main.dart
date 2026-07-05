import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:nova_assistant/services/model_orchestrator.dart';
import 'package:nova_assistant/services/model_manager.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';
import 'package:nova_assistant/services/memory_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flutter Gemma with all available inference engines
  await FlutterGemma.initialize(
    inferenceEngines: const [
      LiteRtLmEngine(), // .litertlm models (Gemma 4, Qwen3, FastVLM, etc.)
      MediaPipeEngine(), // .task models (Gemma3n, Gemma 3, DeepSeek, etc.)
    ],
    maxDownloadRetries: 10,
  );

  // Initialize model manager
  await ModelManager.instance.initialize();

  // Initialize RAG memory
  await MemoryService.initialize();

  // Pre-download and initialize models in background
  _prefetchModels();

  runApp(const NovaApp());
}

Future<void> _prefetchModels() async {
  // Download models in background
  await ModelOrchestrator.instance.prefetchModels();
  // Initialize the default model after download completes
  ModelOrchestrator.instance.initializeDefaultModel();
}

class NovaApp extends StatelessWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nova',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D0D1A),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A2E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const AssistantScreen(),
    );
  }
}
