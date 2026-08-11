import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nova_assistant/screens/assistant_screen.dart';

class OverlayChatScreen extends StatefulWidget {
  const OverlayChatScreen({super.key});

  @override
  State<OverlayChatScreen> createState() => _OverlayChatScreenState();
}

class _OverlayChatScreenState extends State<OverlayChatScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => SystemNavigator.pop(),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = constraints.maxHeight * 0.75;

                  return Container(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0D0D1A),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF6C63FF),
                            ),
                          )
                        : const AssistantScreen(overlayMode: true),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
