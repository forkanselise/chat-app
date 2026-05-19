class Message {
  final String? id;
  final String senderId;
  final String? receiverId;
  final String? groupId;
  final String text;
  final DateTime timestamp;
  final String status; // Sent, Delivered, Read

  Message({
    this.id,
    required this.senderId,
    this.receiverId,
    this.groupId,
    required this.text,
    required this.timestamp,
    this.status = 'Sent',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'groupId': groupId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
    };
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? groupId,
    String? text,
    DateTime? timestamp,
    String? status,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      groupId: groupId ?? this.groupId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
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
      receiverId: (json['receiverId'] ?? json['ReceiverId'])?.toString(),
      groupId: (json['groupId'] ?? json['GroupId'])?.toString(),
      text: (json['text'] ?? json['Text'] ?? '').toString(),
      timestamp: parsedDate,
      status: (json['status'] ?? json['Status'] ?? 'Sent').toString(),
    );
  }
}
