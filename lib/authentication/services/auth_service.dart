import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/app_user.dart';
import '../../utils/constants.dart';
import '../../services/notification_service.dart';

class AuthService {
  static const String _baseUrl = AppConstants.baseUrl;

  Future<AppUser?> register(String name, String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/Auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'Name': name,
        'Email': email,
        'Password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AppUser(id: (data['userId'] ?? data['UserId']).toString(), email: email, name: name);
    } else {
      throw Exception(jsonDecode(response.body));
    }
  }

  Future<AppUser?> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/Auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'Email': email,
        'Password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final user = AppUser.fromJson(data);
      
      final token = data['token'] ?? data['Token'];
      if (token == null) throw Exception('No token received from server');

      // Save token and user info
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token.toString());
      await prefs.setString('user_id', user.id);
      await prefs.setString('user_email', email);
      await prefs.setString('user_name', user.name);

      // Register FCM Token with backend using centralized NotificationService
      await NotificationService().syncToken();

      return user;
    } else {
      throw Exception('Invalid email or password');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<AppUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return null;

    return AppUser(
      id: prefs.getString('user_id') ?? '',
      email: prefs.getString('user_email') ?? '',
      name: prefs.getString('user_name') ?? '',
      token: token,
    );
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }
}
