import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/chat_screen.dart';
import '../screens/group_chat_screen.dart';
import '../utils/constants.dart';

/// Global navigator key to perform routing or display SnackBars without Context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;

  /// Initialize all push notification listeners and handlers
  Future<void> init() async {
    if (_isInitialized) return;

    final messaging = FirebaseMessaging.instance;

    // 1. Request notification permissions
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Handle foreground messages (when the app is open)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundSnackBar(message);
    });

    // 3. Handle messages when the app is clicked from a background state
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _navigateToChat(message);
    });

    // 4. Handle messages when the app is launched from a terminated state
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      // Delay navigation slightly to let the app fully render and load authentication state
      Future.delayed(const Duration(milliseconds: 1200), () {
        _navigateToChat(initialMessage);
      });
    }

    // 5. Handle FCM Token refreshes dynamically
    FirebaseMessaging.instance.onTokenRefresh.listen((fcmToken) async {
      await _syncTokenToBackend(fcmToken);
    });

    // 6. Get current FCM token and sync it to the backend on startup (for already logged-in users)
    try {
      final currentToken = await messaging.getToken();
      if (currentToken != null) {
        await _syncTokenToBackend(currentToken);
      }
    } catch (e) {
      print('Error getting or syncing current FCM token on init: $e');
    }

    _isInitialized = true;
  }

  /// Public method to sync the current FCM token with the backend (e.g. after login/register)
  Future<void> syncToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _syncTokenToBackend(fcmToken);
      } else {
        print('--- FCM WARNING: Obtained null token inside syncToken ---');
      }
    } catch (e) {
      print('--- FCM EXCEPTION in syncToken: $e ---');
    }
  }

  /// Displays a premium custom in-app SnackBar when a message arrives in foreground
  void _showForegroundSnackBar(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;
    final senderId = data['senderId']?.toString();

    if (notification != null) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        final type = data['type']?.toString();
        final isGroup = type == 'group';
        final routeLabel = isGroup ? 'OPEN' : 'CHAT';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
            content: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.message, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title ?? (isGroup ? 'Group Message' : 'New Message'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        notification.body ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: routeLabel,
              textColor: Colors.blueAccent,
              onPressed: () {
                if (isGroup) {
                  final groupId = data['groupId']?.toString();
                  final groupName = data['groupName']?.toString() ?? 'Group Chat';
                  if (groupId != null) {
                    navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => GroupChatScreen(
                          groupId: groupId,
                          groupName: groupName,
                        ),
                      ),
                    );
                  }
                } else if (senderId != null) {
                  navigatorKey.currentState?.push(
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        receiverId: senderId,
                        receiverName: notification.title ?? 'Chat',
                      ),
                    ),
                  );
                }
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Redirect the user directly to the sender's ChatScreen
  void _navigateToChat(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();

    if (type == 'group') {
      final groupId = data['groupId']?.toString();
      final groupName = data['groupName']?.toString() ?? 'Group Chat';
      if (groupId != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        );
      }
    } else {
      final senderId = data['senderId']?.toString();
      final senderName = message.notification?.title ?? 'Chat';

      if (senderId != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              receiverId: senderId,
              receiverName: senderName,
            ),
          ),
        );
      }
    }
  }

  /// Syncs refreshed FCM tokens directly to the .NET Backend
  Future<void> _syncTokenToBackend(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token != null) {
      try {
        print('--- FCM LOG: Attempting to sync token to backend... ---');
        final response = await http.put(
          Uri.parse('${AppConstants.baseUrl}/api/User/fcm-token'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'Token': fcmToken}),
        );
        
        if (response.statusCode == 200) {
          print('--- FCM SUCCESS: FCM Token synced to backend successfully! ---');
        } else {
          print('--- FCM ERROR: Backend rejected token sync. Status: ${response.statusCode}, Body: ${response.body} ---');
        }
      } catch (e) {
        print('--- FCM EXCEPTION: Error syncing refreshed FCM token to backend: $e ---');
      }
    } else {
      print('--- FCM LOG: Skipping token sync, user not logged in yet. ---');
    }
  }
}
