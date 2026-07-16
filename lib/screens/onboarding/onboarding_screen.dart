import 'package:flutter/material.dart';
import 'package:nova_assistant/models/user_preferences.dart';
import 'package:nova_assistant/services/user_preferences_service.dart';
import 'package:nova_assistant/screens/onboarding/welcome_screen.dart';
import 'package:nova_assistant/screens/onboarding/mode_selection_screen.dart';
import 'package:nova_assistant/screens/onboarding/beginner/name_setup_screen.dart';
import 'package:nova_assistant/screens/onboarding/beginner/permissions_screen.dart';
import 'package:nova_assistant/screens/onboarding/beginner/model_download_screen.dart';
import 'package:nova_assistant/screens/onboarding/beginner/ready_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;
  String _userName = '';

  void _nextStep() {
    setState(() => _currentStep++);
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _onModeSelected(UserMode mode) {
    UserPreferencesService.instance.setMode(mode);
    setState(() {
      _currentStep = 1;
    });
  }

  Future<void> _onOnboardingComplete() async {
    await UserPreferencesService.instance.setOnboardingComplete(true);
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/app');
    }
  }

  void _onNameEntered(String name) {
    UserPreferencesService.instance.setUserName(name);
    setState(() => _userName = name);
    _nextStep();
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return WelcomeScreen(onGetStarted: () => _nextStep());
      case 1:
        return ModeSelectionScreen(
          onModeSelected: _onModeSelected,
          onBack: _previousStep,
        );
      case 2:
        return NameSetupScreen(onNameEntered: _onNameEntered);
      case 3:
        return PermissionsScreen(
          userName: _userName,
          onPermissionsGranted: _nextStep,
        );
      case 4:
        return ModelDownloadScreen(onDownloadComplete: _nextStep);
      case 5:
        return ReadyScreen(
          userName: _userName,
          onStartChatting: _onOnboardingComplete,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildCurrentStep(),
        ),
      ),
    );
  }
}
