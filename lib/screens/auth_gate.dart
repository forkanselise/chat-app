import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_mode_provider.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'mode_selection_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final chatMode = ref.watch(chatModeProvider);

    if (user != null) {
      if (chatMode == null) {
        return const ModeSelectionScreen();
      }
      return const HomeScreen();
    } else {
      return const LoginScreen();
    }
  }
}
