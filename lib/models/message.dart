class Message {
  final String? id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime timestamp;
  final String status; // Sent, Delivered, Read

  Message({
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    this.status = 'Sent',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      final dateStr = (json['timestamp'] ?? json['Timestamp'])?.toString();
      parsedDate = dateStr != null ? DateTime.parse(dateStr).toLocal() : DateTime.now();
    } catch (e) {
      parsedDate = DateTime.now();
    }

    return Message(
      id: (json['id'] ?? json['Id'])?.toString(),
      senderId: (json['senderId'] ?? json['SenderId'] ?? '').toString(),
      receiverId: (json['receiverId'] ?? json['ReceiverId'] ?? '').toString(),
      text: (json['text'] ?? json['Text'] ?? '').toString(),
      timestamp: parsedDate,
      status: (json['status'] ?? json['Status'] ?? 'Sent').toString(),
    );
  }
}
