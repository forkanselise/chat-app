import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:async/async.dart';
import '../models/message.dart';
import '../models/app_user.dart';
import '../utils/constants.dart';

class ChatService {
  static const String _baseUrl = AppConstants.baseUrl;
  static const String _usersCacheKey = 'cached_users_v1';
  static const String _conversationCachePrefix = 'cached_messages_v1_';
  static const String _groupCachePrefix = 'cached_group_messages_v1_';
  static const String _pendingOutboxPrefix = 'pending_messages_v1_';
  static const Duration _dedupWindow = Duration(seconds: 20);

  final _localUpdateController = StreamController<String>.broadcast();
  Stream<String> get localUpdateStream => _localUpdateController.stream;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  StreamSubscription<ConnectivityResult>? _connectivitySub;

  /// Start listening for connectivity changes to auto-flush pending messages.
  void initConnectivity() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none) {
        await _flushAllPending();
      }
    });
  }

  /// Stop listening for connectivity changes.
  void disposeConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  String _conversationKey(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return ids.join('_');
  }

  String _conversationCacheKey(String userA, String userB) {
    return '$_conversationCachePrefix${_conversationKey(userA, userB)}';
  }

  String _pendingOutboxKey(String userA, String userB) {
    return '$_pendingOutboxPrefix${_conversationKey(userA, userB)}';
  }

  int _statusRank(String status) {
    switch (status) {
      case 'Read':
        return 3;
      case 'Delivered':
        return 2;
      case 'Sent':
        return 1;
      default:
        return 0;
    }
  }

  bool _sameMessage(Message first, Message second) {
    if (first.id != null && second.id != null && first.id == second.id) {
      return true;
    }

    if (first.senderId != second.senderId) return false;
    if (first.receiverId != second.receiverId) return false;
    if (first.text != second.text) return false;

    return first.timestamp.difference(second.timestamp).abs() <= _dedupWindow;
  }

  List<Message> _mergeMessages(List<Message> first, List<Message> second) {
    final merged = <Message>[];

    for (final candidate in [...first, ...second]) {
      final existingIndex = merged.indexWhere((message) => _sameMessage(message, candidate));

      if (existingIndex == -1) {
        merged.add(candidate);
        continue;
      }

      final existing = merged[existingIndex];
      merged[existingIndex] = _statusRank(candidate.status) >= _statusRank(existing.status) ? candidate : existing;
    }

    merged.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return merged;
  }

  Future<List<AppUser>> _readCachedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersCacheKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data.map((item) => AppUser.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeCachedUsers(List<AppUser> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersCacheKey, jsonEncode(users.map((user) => user.toJson()).toList()));
  }

  Future<List<Message>> _readCachedMessages(String currentUserId, String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationCacheKey(currentUserId, otherUserId));

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data.map((item) => Message.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeCachedMessages(String currentUserId, String otherUserId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _conversationCacheKey(currentUserId, otherUserId),
      jsonEncode(messages.map((message) => message.toJson()).toList()),
    );
    _localUpdateController.add(otherUserId);
  }

  Future<List<Message>> _readPendingMessages(String currentUserId, String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingOutboxKey(currentUserId, otherUserId));

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data.map((item) => Message.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePendingMessages(String currentUserId, String otherUserId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingOutboxKey(currentUserId, otherUserId),
      jsonEncode(messages.map((message) => message.toJson()).toList()),
    );
    _localUpdateController.add(otherUserId);
  }

  Future<void> _storeConversationMessage(String currentUserId, String otherUserId, Message message) async {
    final cached = await _readCachedMessages(currentUserId, otherUserId);
    final merged = _mergeMessages(cached, [message]);
    await _writeCachedMessages(currentUserId, otherUserId, merged);
  }

  Future<void> _removePendingMessage(String currentUserId, String otherUserId, String messageId) async {
    final pending = await _readPendingMessages(currentUserId, otherUserId);
    final updated = pending.where((message) => message.id != messageId).toList();
    await _writePendingMessages(currentUserId, otherUserId, updated);
  }

  Future<void> _markConversationMessages(
    String currentUserId,
    String otherUserId,
    bool Function(Message message) shouldUpdate,
    Message Function(Message message) update,
  ) async {
    final cached = await _readCachedMessages(currentUserId, otherUserId);
    final updated = cached.map((message) => shouldUpdate(message) ? update(message) : message).toList();
    await _writeCachedMessages(currentUserId, otherUserId, updated);
  }

  /// Posts a message to the server and returns parsed response (message JSON) on success, otherwise null.
  Future<Map<String, dynamic>?> _postMessageToServer(String token, Message message) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/Message'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'ReceiverId': message.receiverId, 'Text': message.text}),
    );

    if (response.statusCode == 200) {
      try {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        return parsed;
      } catch (_) {
        return <String, dynamic>{};
      }
    }

    return null;
  }

  Future<void> _flushAllPending() async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId == null) return;

    final users = await _readCachedUsers();
    for (final user in users) {
      if (user.id == currentUserId) continue;
      await _flushPendingForConversation(currentUserId, user.id);
    }
  }

  Future<void> _flushPendingForConversation(String currentUserId, String otherUserId) async {
    final token = await _getToken();
    if (token == null) return;

    final pending = await _readPendingMessages(currentUserId, otherUserId);
    if (pending.isEmpty) return;

    for (final message in pending) {
      int attempt = 0;
      while (attempt < 3) {
        attempt += 1;
        try {
          final serverResp = await _postMessageToServer(token, message);
          if (serverResp != null) {
            await _removePendingMessage(currentUserId, otherUserId, message.id!);

            try {
              final serverMsg = Message.fromJson(serverResp);
              await _storeConversationMessage(currentUserId, otherUserId, serverMsg.copyWith(status: 'Delivered'));
            } catch (_) {
              await _markConversationMessages(
                currentUserId,
                otherUserId,
                (m) => m.id == message.id,
                (m) => m.copyWith(status: 'Delivered'),
              );
            }

            break;
          }
        } catch (_) {
          // ignore and retry
        }

        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
  }

  // Get all users
  Future<List<AppUser>> getUsers() async {
    final token = await _getToken();
    if (token == null) {
      return _readCachedUsers();
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/User'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        final users = data.map((json) => AppUser.fromJson(Map<String, dynamic>.from(json as Map))).toList();
        await _writeCachedUsers(users);
        return users;
      }
    } catch (_) {
      // Fall through to cached data.
    }

    return _readCachedUsers();
  }

  // Send message
  Future<void> sendMessage(String receiverId, String text) async {
    final token = await _getToken();
    final currentUserId = await _getCurrentUserId();

    if (token == null || currentUserId == null) {
      throw Exception('Not authenticated');
    }

    final localMessage = Message(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderId: currentUserId,
      receiverId: receiverId,
      text: text,
      timestamp: DateTime.now(),
      status: 'Sent',
    );

    await _storeConversationMessage(currentUserId, receiverId, localMessage);
    await _writePendingMessages(currentUserId, receiverId, [
      ...await _readPendingMessages(currentUserId, receiverId),
      localMessage,
    ]);

    try {
      final serverResp = await _postMessageToServer(token, localMessage);
      if (serverResp != null) {
        await _removePendingMessage(currentUserId, receiverId, localMessage.id!);

        if (serverResp.isNotEmpty) {
          try {
            final serverMsg = Message.fromJson(serverResp);
            await _storeConversationMessage(currentUserId, receiverId, serverMsg.copyWith(status: 'Delivered'));
          } catch (_) {
            await _markConversationMessages(
              currentUserId,
              receiverId,
              (message) => message.id == localMessage.id,
              (message) => message.copyWith(status: 'Delivered'),
            );
          }
        } else {
          await _markConversationMessages(
            currentUserId,
            receiverId,
            (message) => message.id == localMessage.id,
            (message) => message.copyWith(status: 'Delivered'),
          );
        }
      }
    } catch (_) {
      // Keep the locally queued message for retry when connectivity returns.
    }
  }

  // Get conversation history
  Future<List<Message>> getMessages(String otherUserId) async {
    final token = await _getToken();
    final currentUserId = await _getCurrentUserId();

    if (currentUserId == null) {
      return [];
    }

    final cachedMessages = await _readCachedMessages(currentUserId, otherUserId);
    final pendingMessages = await _readPendingMessages(currentUserId, otherUserId);

    if (token == null) {
      return _mergeMessages(cachedMessages, pendingMessages);
    }

    try {
      final pendingBeforeSync = await _readPendingMessages(currentUserId, otherUserId);
      for (final pendingMessage in pendingBeforeSync) {
        final serverResp = await _postMessageToServer(token, pendingMessage);
        if (serverResp != null) {
          await _removePendingMessage(currentUserId, otherUserId, pendingMessage.id!);
          if (serverResp.isNotEmpty) {
            try {
              final serverMsg = Message.fromJson(serverResp);
              await _storeConversationMessage(currentUserId, otherUserId, serverMsg.copyWith(status: 'Delivered'));
            } catch (_) {
              await _markConversationMessages(
                currentUserId,
                otherUserId,
                (m) => m.id == pendingMessage.id,
                (m) => m.copyWith(status: 'Delivered'),
              );
            }
          } else {
            await _markConversationMessages(
              currentUserId,
              otherUserId,
              (m) => m.id == pendingMessage.id,
              (m) => m.copyWith(status: 'Delivered'),
            );
          }
        }
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/Message/$otherUserId'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        final remoteMessages = data.map((json) => Message.fromJson(Map<String, dynamic>.from(json as Map))).toList();

        final freshPending = await _readPendingMessages(currentUserId, otherUserId);
        final merged = _mergeMessages(remoteMessages, [...cachedMessages, ...freshPending]);
        await _writeCachedMessages(currentUserId, otherUserId, merged);
        return merged;
      }
    } catch (_) {
      // Fall through to cached data.
    }

    return _mergeMessages(cachedMessages, pendingMessages);
  }

  // Mark messages as read
  Future<void> markAsRead(String senderId) async {
    final token = await _getToken();
    final currentUserId = await _getCurrentUserId();

    if (currentUserId != null) {
      await _markConversationMessages(
        currentUserId,
        senderId,
        (message) => message.senderId == senderId && message.receiverId == currentUserId,
        (message) => message.copyWith(status: 'Read'),
      );
    }

    if (token == null) {
      return;
    }

    try {
      await http.post(
        Uri.parse('$_baseUrl/api/Message/read/$senderId'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
    } catch (_) {
      // Ignore read-receipt sync failures when offline.
    }
  }

  // Mark our sent messages as read in the local cache
  Future<void> markSentMessagesAsRead(String otherUserId) async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId == null) return;

    await _markConversationMessages(
      currentUserId,
      otherUserId,
      (message) => message.senderId == currentUserId && message.receiverId == otherUserId,
      (message) => message.copyWith(status: 'Read'),
    );
  }

  // Stream for users (polling)
  Stream<List<AppUser>> getUsersStream() async* {
    while (true) {
      final users = await getUsers();
      yield users;
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  // Save an incoming message to the local cache and notify listeners
  Future<void> saveReceivedMessage(String otherUserId, Message message) async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId == null) return;
    await _storeConversationMessage(currentUserId, otherUserId, message);
  }

  // Get local messages only (from cache + outbox) without hitting network
  Future<List<Message>> getLocalMessages(String otherUserId) async {
    final currentUserId = await _getCurrentUserId();
    if (currentUserId == null) return [];

    final cached = await _readCachedMessages(currentUserId, otherUserId);
    final pending = await _readPendingMessages(currentUserId, otherUserId);
    return _mergeMessages(cached, pending);
  }

  // Stream for messages (polling)
  Stream<List<Message>> getMessagesStream(String otherUserId) async* {
    yield await getMessages(otherUserId);

    final combined = StreamGroup.merge([
      Stream.periodic(const Duration(seconds: 2)),
      localUpdateStream.where((uid) => uid == otherUserId),
    ]);

    await for (final _ in combined) {
      yield await getMessages(otherUserId);
    }
  }

  // --- Group Chat Caching and API Handling ---

  Future<List<Message>> _readCachedGroupMessages(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_groupCachePrefix$groupId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data.map((item) => Message.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeCachedGroupMessages(String groupId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_groupCachePrefix$groupId',
      jsonEncode(messages.map((message) => message.toJson()).toList()),
    );
    _localUpdateController.add(groupId);
  }

  Future<void> saveGroupMessage(String groupId, Message message) async {
    final cached = await _readCachedGroupMessages(groupId);
    final merged = _mergeMessages(cached, [message]);
    await _writeCachedGroupMessages(groupId, merged);
  }

  Future<List<Message>> getLocalGroupMessages(String groupId) async {
    return await _readCachedGroupMessages(groupId);
  }

  Future<List<Message>> getGroupMessages(String groupId) async {
    final token = await _getToken();
    final cachedMessages = await _readCachedGroupMessages(groupId);

    if (token == null) {
      return cachedMessages;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/Group/$groupId/messages'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        final remoteMessages = data.map((json) => Message.fromJson(Map<String, dynamic>.from(json as Map))).toList();

        final merged = _mergeMessages(remoteMessages, cachedMessages);
        await _writeCachedGroupMessages(groupId, merged);
        return merged;
      }
    } catch (_) {
      // Fall through to cached data
    }
    return cachedMessages;
  }

  Future<void> sendGroupMessage(String groupId, String text) async {
    final token = await _getToken();
    final currentUserId = await _getCurrentUserId();

    if (token == null || currentUserId == null) {
      throw Exception('Not authenticated');
    }

    // Call POST API
    final response = await http.post(
      Uri.parse('$_baseUrl/api/Group/$groupId/message'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'Text': text}),
    );

    if (response.statusCode == 200) {
      try {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        final serverMsg = Message.fromJson(parsed);
        await saveGroupMessage(groupId, serverMsg);
      } catch (_) {}
    } else {
      throw Exception('Failed to send group message: ${response.statusCode}');
    }
  }

  Stream<List<Message>> getGroupMessagesStream(String groupId) async* {
    yield await getGroupMessages(groupId);

    final combined = StreamGroup.merge([
      Stream.periodic(const Duration(seconds: 2)),
      localUpdateStream.where((uid) => uid == groupId),
    ]);

    await for (final _ in combined) {
      yield await getGroupMessages(groupId);
    }
  }
}
