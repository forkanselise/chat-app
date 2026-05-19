import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/constants.dart'; // define baseUrl here if not existing
import '../providers/auth_provider.dart';
import 'group_chat_screen.dart'; // assume exists

// Simple Group model
class Group {
  final String id;
  final String name;
  Group({required this.id, required this.name});

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['_id'] ?? json['id'] ?? '',
        name: json['name'] ?? 'Unnamed',
      );
}

// Provider that fetches groups for the logged‑in user
final groupListProvider = FutureProvider.autoDispose<List<Group>>((ref) async {
  // Replace with your auth token provider
  final token = await ref.read(authProvider.notifier).getToken();
  final response = await http.get(
    Uri.parse('${AppConstants.baseUrl}/api/Group'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200) {
    throw Exception('Failed to load groups');
  }
  final List<dynamic> jsonList = jsonDecode(response.body);
  return jsonList.map((e) => Group.fromJson(e)).toList();
});

class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(groupListProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'My Groups',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: asyncGroups.when(
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(child: Text('No groups yet. Create one!'));
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (ctx, i) {
              final g = groups[i];
              return ListTile(
                leading: const Icon(Icons.group),
                title: Text(g.name),
                onTap: () {
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => GroupChatScreen(groupId: g.id, groupName: g.name),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
