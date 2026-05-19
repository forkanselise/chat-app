import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_mode_provider.dart';
import '../utils/date_formatter.dart';
import 'chat_screen.dart';
import '../screens/group_list_screen.dart';
import '../screens/group_create_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(chatModeProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(chatModeProvider.notifier).state = null,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat App'),
            Text(
              mode == ChatMode.signalR ? 'Socket Mode' : 'Polling Mode',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(chatModeProvider.notifier).state = null;
              ref.read(authProvider.notifier).logout();
            },
            icon: const Icon(Icons.power_settings_new),
          ),
          IconButton(
            tooltip: 'My Groups',
            icon: const Icon(Icons.group),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupListScreen()));
            },
          ),
        ],
      ),
      body: _buildUserList(ref),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create a new group',
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => GroupCreateScreen()));
        },
      ),
    );
  }

  Widget _buildUserList(WidgetRef ref) {
    final usersStream = ref.watch(usersStreamProvider);
    final currentUser = ref.watch(authProvider);

    return usersStream.when(
      data: (users) {
        final otherUsers = users.where((u) => u.id != currentUser?.id).toList();

        if (otherUsers.isEmpty) {
          return const Center(child: Text('No other users found.'));
        }

        return ListView.builder(
          itemCount: otherUsers.length,
          itemBuilder: (context, index) {
            final user = otherUsers[index];
            return ListTile(
              leading: Stack(
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: user.isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(user.name),
              subtitle: Text(user.isOnline ? 'Online' : formatLastSeen(user.lastSeen)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(receiverName: user.name, receiverId: user.id),
                  ),
                );
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }
}
