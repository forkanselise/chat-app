import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ChatMode { polling, signalR }

final chatModeProvider = StateProvider<ChatMode?>((ref) => null);
