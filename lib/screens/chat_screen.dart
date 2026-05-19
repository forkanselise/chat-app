import 'dart:async';

import 'package:chat_app/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_mode_provider.dart';
import '../models/message.dart';
import 'package:intl/intl.dart';
import '../utils/date_formatter.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String receiverName;
  final String receiverId;

  const ChatScreen({super.key, required this.receiverName, required this.receiverId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _typingSubscription;
  Timer? _typingTimer;
  bool _isReceiverTyping = false;
  bool _sentTyping = false;

  @override
  void initState() {
    super.initState();
    // Mark messages as read when opening the chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatServiceProvider).markAsRead(widget.receiverId);
      // subscribe to typing notifications if using SignalR
      final mode = ref.read(chatModeProvider);
      if (mode == ChatMode.signalR) {
        final signalR = ref.read(signalRServiceProvider);
        _typingSubscription = signalR.typingStream.listen((event) {
          try {
            final userId = event['userId']?.toString();
            final isTyping = event['isTyping'] == true || event['isTyping'] == 'true';
            if (userId == widget.receiverId) {
              setState(() => _isReceiverTyping = isTyping);
            }
          } catch (_) {}
        });
      }
    });
  }

  @override
  void dispose() {
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      final text = _messageController.text;
      _messageController.clear();

      try {
        // Always send via HTTP to ensure it's saved in the DB
        // The backend will automatically notify the SignalR hub for us!
        await ref.read(chatServiceProvider).sendMessage(widget.receiverId, text);
        _scrollToBottom();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
        }
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(chatModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Consumer(
          builder: (context, ref, child) {
            final usersAsync = ref.watch(usersStreamProvider);
            return usersAsync.when(
              data: (users) {
                final receiver = users.cast<AppUser?>().firstWhere(
                  (u) => u?.id == widget.receiverId,
                  orElse: () => null,
                );
                final isOnline = receiver?.isOnline ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.receiverName),
                    Text(
                      _isReceiverTyping ? 'typing...' : (isOnline ? 'Active Now' : formatLastSeen(receiver?.lastSeen)),
                      style: TextStyle(
                        fontSize: 12,
                        color: _isReceiverTyping
                            ? Colors.yellowAccent
                            : (isOnline ? Colors.greenAccent : Colors.white70),
                      ),
                    ),
                  ],
                );
              },
              loading: () => Text(widget.receiverName),
              error: (_, __) => Text(widget.receiverName),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final messagesStream = ref.watch(messagesStreamProvider(widget.receiverId));
    final currentUser = ref.watch(authProvider);

    return messagesStream.when(
      data: (messages) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollController,
          itemCount: messages.length + (_isReceiverTyping ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return _buildTypingIndicatorItem();
            }
            final message = messages[index];
            return _buildMessageItem(message, currentUser?.id);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildTypingIndicatorItem() {
    return Container(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.receiverName} is typing something',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[500]!),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(Message message, String? currentUserId) {
    bool isCurrentUser = message.senderId == currentUserId;
    final isRead = message.status == 'Read';
    final isDelivered = message.status == 'Delivered' || isRead;

    return Container(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isCurrentUser ? Colors.blueAccent : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: isCurrentUser ? Colors.white : Colors.black87, fontSize: 16),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('hh:mm a').format(message.timestamp),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (isCurrentUser) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead || isDelivered ? Icons.done_all : Icons.done,
                    size: 14,
                    color: isRead ? Colors.blue : Colors.grey,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onChanged: (text) {
                  // send typing events when in SignalR mode
                  final mode = ref.read(chatModeProvider);
                  if (mode == ChatMode.signalR) {
                    final signalR = ref.read(signalRServiceProvider);
                    if (!_sentTyping) {
                      signalR.sendTyping(widget.receiverId, true);
                      _sentTyping = true;
                    }

                    _typingTimer?.cancel();
                    _typingTimer = Timer(const Duration(seconds: 2), () {
                      signalR.sendTyping(widget.receiverId, false);
                      _sentTyping = false;
                    });
                  }
                },
                onSubmitted: (_) => sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: IconButton(
                onPressed: sendMessage,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
