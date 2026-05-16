import 'dart:async';
import 'package:signalr_netcore/signalr_client.dart';
import '../utils/constants.dart';
import '../models/message.dart';

class SignalRService {
  HubConnection? _hubConnection;
  final _messageController = StreamController<Message>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _readReceiptController = StreamController<String>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;
  Stream<String> get readReceiptStream => _readReceiptController.stream;

  Future<void> init(String token) async {
    if (_hubConnection?.state == HubConnectionState.Connected) return;

    _hubConnection = HubConnectionBuilder()
        .withUrl(
          '${AppConstants.baseUrl}/chatHub',
          options: HttpConnectionOptions(
            accessTokenFactory: () async => token,
          ),
        )
        .withAutomaticReconnect()
        .build();

    // Listen for incoming messages
    _hubConnection!.on('ReceiveMessage', (arguments) {
      if (arguments != null && arguments.length >= 2) {
        final senderId = arguments[0].toString();
        final text = arguments[1].toString();
        
        _messageController.add(Message(
          senderId: senderId,
          receiverId: 'me', // Simplified
          text: text,
          timestamp: DateTime.now(),
        ));
      }
    });

    // Listen for user online/offline status changes
    _hubConnection!.on('UserStatusChanged', (arguments) {
      if (arguments != null && arguments.length >= 2) {
        _statusController.add({
          'userId': arguments[0],
          'isOnline': arguments[1],
        });
      }
    });

    // Listen for read receipts
    _hubConnection!.on('MessagesRead', (arguments) {
      if (arguments != null && arguments.isNotEmpty) {
        _readReceiptController.add(arguments[0].toString());
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

  void dispose() {
    _hubConnection?.stop();
    _messageController.close();
    _statusController.close();
    _readReceiptController.close();
  }
}
