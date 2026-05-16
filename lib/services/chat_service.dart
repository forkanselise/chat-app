import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/app_user.dart';
import '../utils/constants.dart';

class ChatService {
  static const String _baseUrl = AppConstants.baseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Get all users
  Future<List<AppUser>> getUsers() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/api/User'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AppUser.fromJson(json)).toList();
    } else {
      throw Exception('Users Error (${response.statusCode}): ${response.body}');
    }
  }

  // Send message
  Future<void> sendMessage(String receiverId, String text) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/Message'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'ReceiverId': receiverId,
        'Text': text,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Send Error (${response.statusCode}): ${response.body}');
    }
  }

  // Get conversation history
  Future<List<Message>> getMessages(String otherUserId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/api/Message/$otherUserId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Message.fromJson(json)).toList();
    } else {
      throw Exception('Load Error (${response.statusCode}): ${response.body}');
    }
  }

  // Mark messages as read
  Future<void> markAsRead(String senderId) async {
    final token = await _getToken();
    await http.post(
      Uri.parse('$_baseUrl/api/Message/read/$senderId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  // Stream for users (polling)
  Stream<List<AppUser>> getUsersStream() async* {
    while (true) {
      try {
        final users = await getUsers();
        yield users;
      } catch (e) {
        yield [];
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  // Stream for messages (polling)
  Stream<List<Message>> getMessagesStream(String otherUserId) async* {
    while (true) {
      try {
        final messages = await getMessages(otherUserId);
        yield messages;
      } catch (e) {
        rethrow; 
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }
}
