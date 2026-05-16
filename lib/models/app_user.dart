class AppUser {
  final String id;
  final String email;
  final String name;
  final String? token;
  final bool isOnline;
  final DateTime? lastSeen;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.token,
    this.isOnline = false,
    this.lastSeen,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['UserId'] ?? json['userId'] ?? json['id'] ?? json['Id'] ?? '').toString(),
      email: (json['email'] ?? json['Email'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? 'No Name').toString(),
      token: (json['token'] ?? json['Token'])?.toString(),
      isOnline: json['isOnline'] ?? json['IsOnline'] ?? false,
      lastSeen: json['lastSeen'] != null || json['LastSeen'] != null
          ? DateTime.parse((json['lastSeen'] ?? json['LastSeen']).toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'token': token,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }
}
