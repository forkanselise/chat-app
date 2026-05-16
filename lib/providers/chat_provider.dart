import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:async/async.dart';
import '../services/chat_service.dart';
import '../services/signalr_service.dart';
import '../models/app_user.dart';
import '../models/message.dart';
import 'chat_mode_provider.dart';
import 'auth_provider.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

final signalRServiceProvider = Provider<SignalRService>((ref) {
  final service = SignalRService();
  final user = ref.watch(authProvider);
  if (user?.token != null) {
    service.init(user!.token!);
  }
  ref.onDispose(() => service.dispose());
  return service;
});

final usersStreamProvider = StreamProvider<List<AppUser>>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  final mode = ref.watch(chatModeProvider);

  if (mode == ChatMode.signalR) {
    final signalRService = ref.watch(signalRServiceProvider);
    
    // Create a stream that combines initial polling with real-time status updates
    return _buildUserStatusStream(chatService, signalRService);
  } else {
    return chatService.getUsersStream();
  }
});

Stream<List<AppUser>> _buildUserStatusStream(
  ChatService chatService, 
  SignalRService signalRService
) async* {
  // 1. Initial fetch
  List<AppUser> users = await chatService.getUsers();
  yield users;

  // 2. Listen for real-time status changes from SignalR
  await for (final statusUpdate in signalRService.statusStream) {
    final userId = statusUpdate['userId'];
    final isOnline = statusUpdate['isOnline'];

    users = users.map((u) {
      if (u.id == userId) {
        return AppUser(
          id: u.id,
          email: u.email,
          name: u.name,
          token: u.token,
          isOnline: isOnline,
          lastSeen: DateTime.now(),
        );
      }
      return u;
    }).toList();
    
    yield users;
  }
}

final messagesStreamProvider = StreamProvider.family<List<Message>, String>((ref, otherUserId) {
  final mode = ref.watch(chatModeProvider);
  final chatService = ref.watch(chatServiceProvider);
  
  if (mode == ChatMode.signalR) {
    final signalRService = ref.watch(signalRServiceProvider);
    final currentUser = ref.watch(authProvider);
    
    // Create a stream that starts with history and then yields new SignalR messages
    return _buildSignalRStream(chatService, signalRService, otherUserId, currentUser?.id ?? '');
  } else {
    return chatService.getMessagesStream(otherUserId);
  }
});

Stream<List<Message>> _buildSignalRStream(
  ChatService chatService, 
  SignalRService signalRService, 
  String otherUserId,
  String currentUserId,
) async* {
  // 1. Fetch History first
  List<Message> history = await chatService.getMessages(otherUserId);
  yield history;

  // 2. Listen for new messages OR read receipts from SignalR
  final combinedStream = StreamGroup.merge([
    signalRService.messageStream.map((m) => {'type': 'msg', 'data': m}),
    signalRService.readReceiptStream.map((r) => {'type': 'read', 'data': r}),
  ]);

  await for (final event in combinedStream) {
    if (event['type'] == 'msg') {
      final newMessage = event['data'] as Message;
      if (newMessage.senderId == otherUserId || newMessage.senderId == currentUserId) {
        history = [...history, newMessage];
        yield history;
      }
    } else if (event['type'] == 'read') {
      final readerId = event['data'] as String;
      if (readerId == otherUserId) {
        // The other person read my messages!
        history = history.map((m) {
          if (m.senderId == currentUserId && m.status != 'Read') {
            return Message(
              id: m.id,
              senderId: m.senderId,
              receiverId: m.receiverId,
              text: m.text,
              timestamp: m.timestamp,
              status: 'Read',
            );
          }
          return m;
        }).toList();
        yield history;
      }
    }
  }
}
