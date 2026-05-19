import 'dart:async';
import 'package:signalr_netcore/signalr_client.dart';
import '../utils/constants.dart';
import '../models/message.dart';

class SignalRService {
  HubConnection? _hubConnection;
  final _messageController = StreamController<Message>.broadcast();
  final _groupMessageController = StreamController<Message>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _readReceiptController = StreamController<String>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Message> get groupMessageStream => _groupMessageController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<String> get readReceiptStream => _readReceiptController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;

  Future<void> init(String token) async {
    if (_hubConnection?.state == HubConnectionState.Connected) return;

    _hubConnection = HubConnectionBuilder()
        .withUrl(
          '${AppConstants.baseUrl}/chatHub',
          options: HttpConnectionOptions(accessTokenFactory: () async => token),
        )
        .withAutomaticReconnect()
        .build();

    // Listen for incoming messages
    _hubConnection!.on('ReceiveMessage', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        try {
          final data = arguments[0];
          if (data is Map) {
            final parsed = Map<String, dynamic>.from(data);
            final message = Message.fromJson(parsed);
            _messageController.add(message);
          }
        } catch (e) {
          print('Error parsing received SignalR message: $e');
        }
      }
    });

    // Listen for user online/offline status changes
    _hubConnection!.on('UserStatusChanged', (arguments) {
      if (arguments != null && arguments.length >= 2) {
        _statusController.add({'userId': arguments[0], 'isOnline': arguments[1]});
      }
    });

    // Listen for typing notifications: arguments => [userId, isTyping]
    _hubConnection!.on('UserTyping', (arguments) {
      if (arguments != null && arguments.length >= 2) {
        _typingController.add({'userId': arguments[0].toString(), 'isTyping': arguments[1]});
      }
    });

    // Listen for read receipts
    _hubConnection!.on('MessagesRead', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        _readReceiptController.add(arguments[0].toString());
      }
    });

    // Listen for group messages
    _hubConnection!.on('ReceiveGroupMessage', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        try {
          final data = arguments[0];
          if (data is Map) {
            final parsed = Map<String, dynamic>.from(data);
            final message = Message.fromJson(parsed);
            _groupMessageController.add(message);
          }
        } catch (e) {
          print('Error parsing received SignalR group message: $e');
        }
      }
    });

    try {
      await _hubConnection!.start();
      print('SignalR Connected');
    } catch (e) {
      print('SignalR Connection Error: $e');
    }
  }

  Future<void> sendMessage(String receiverId, String text) async {
    if (_hubConnection?.state == HubConnectionState.Connected) {
      await _hubConnection!.invoke('SendMessageToUser', args: [receiverId, text]);
    }
  }

  /// Notify the server that the current user is typing (or stopped typing).
  Future<void> sendTyping(String receiverId, bool isTyping) async {
    if (_hubConnection?.state == HubConnectionState.Connected) {
      try {
        await _hubConnection!.invoke('SendTyping', args: [receiverId, isTyping]);
      } catch (_) {
        // ignore
      }
    }
  }

  void dispose() {
    _hubConnection?.stop();
    _messageController.close();
    _groupMessageController.close();
    _statusController.close();
    _readReceiptController.close();
    _typingController.close();
  }
}
