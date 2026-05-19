import 'package:intl/intl.dart';

String formatLastSeen(DateTime? lastSeen) {
  if (lastSeen == null) return 'Offline';
  
  // Convert lastSeen to local time zone if it is in UTC
  final localLastSeen = lastSeen.toLocal();
  final now = DateTime.now();
  final difference = now.difference(localLastSeen);

  if (difference.isNegative || difference.inSeconds < 30) {
    return 'Last seen just now';
  } else if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return 'Last seen ${minutes == 0 ? 1 : minutes}m ago';
  } else if (difference.inHours < 24) {
    return 'Last seen ${difference.inHours}h ago';
  } else if (difference.inDays == 1) {
    return 'Last seen yesterday';
  } else if (difference.inDays < 7) {
    return 'Last seen ${difference.inDays}d ago';
  } else {
    return 'Last seen on ${DateFormat('MMM d, yyyy').format(localLastSeen)}';
  }
}
