import 'package:cloud_firestore/cloud_firestore.dart';

import 'property.dart';

/// One side of a chat — what the other person sees in the header and inbox.
class ChatPerson {
  final String uid;
  final String name;
  final String? avatarUrl;
  final bool verified;

  /// Supabase agent id, when this person lists homes (opens their profile).
  final String? agentId;

  const ChatPerson({
    required this.uid,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.agentId,
  });

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    final letters = parts.take(2).map((e) => e[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'avatar': avatarUrl,
        'verified': verified,
        'agentId': agentId,
      };

  factory ChatPerson.fromMap(String uid, Map<String, dynamic>? m) => ChatPerson(
        uid: uid,
        name: (m?['name'] as String?)?.trim().isNotEmpty == true
            ? m!['name'] as String
            : 'Home8 user',
        avatarUrl: m?['avatar'] as String?,
        verified: m?['verified'] as bool? ?? false,
        agentId: m?['agentId'] as String?,
      );
}

/// The listing a conversation is about ("Home in Palm Jumeirah · 96k/yr").
class ChatListing {
  final String id;
  final String title;
  final String priceLabel;
  final String? imageUrl;

  const ChatListing({
    required this.id,
    required this.title,
    required this.priceLabel,
    this.imageUrl,
  });

  factory ChatListing.fromProperty(Property p) => ChatListing(
        id: p.id,
        title: p.title,
        priceLabel: shortPrice(p.price, p.purpose == Purpose.rent ? p.period : null),
        imageUrl: p.photos.isEmpty ? null : p.photos.first,
      );

  /// "96k/yr", "1.2M", "450/night".
  static String shortPrice(int price, RentPeriod? period) {
    String n;
    if (price >= 1000000) {
      final m = price / 1000000;
      final s = m >= 10 ? '${m.round()}' : m.toStringAsFixed(1);
      n = '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}M';
    } else if (price >= 1000) {
      n = '${(price / 1000).round()}k';
    } else {
      n = '$price';
    }
    final suffix = switch (period) {
      RentPeriod.yearly => '/yr',
      RentPeriod.monthly => '/mo',
      RentPeriod.weekly => '/wk',
      RentPeriod.nightly => '/night',
      null => '',
    };
    return '$n$suffix';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'price': priceLabel,
        'image': imageUrl,
      };

  static ChatListing? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['id'] == null) return null;
    return ChatListing(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      priceLabel: m['price'] as String? ?? '',
      imageUrl: m['image'] as String?,
    );
  }
}

/// A conversation between two people (optionally about one listing).
class Conversation {
  final String id;
  final List<String> members;
  final Map<String, ChatPerson> people;
  final ChatListing? listing;
  final String lastText;
  final String? lastSender;
  final DateTime? updatedAt;
  final Map<String, int> unread;
  final Map<String, DateTime> readAt;
  /// When each member last said "I'm typing" (null = not typing). The
  /// app refreshes it every few seconds while typing, so a stale value
  /// from a closed app can be ignored.
  final Map<String, DateTime?> typing;

  const Conversation({
    required this.id,
    required this.members,
    required this.people,
    this.listing,
    this.lastText = '',
    this.lastSender,
    this.updatedAt,
    this.unread = const {},
    this.readAt = const {},
    this.typing = const {},
  });

  String otherUid(String me) =>
      members.firstWhere((m) => m != me, orElse: () => me);

  ChatPerson other(String me) {
    final uid = otherUid(me);
    return people[uid] ?? ChatPerson(uid: uid, name: 'Home8 user');
  }

  int unreadFor(String uid) => unread[uid] ?? 0;

  bool hasMessages(String me) => lastSender != null;

  factory Conversation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final members = [for (final m in (d['members'] as List? ?? const [])) '$m'];
    final peopleRaw = (d['people'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Conversation(
      id: doc.id,
      members: members,
      people: {
        for (final uid in members)
          uid: ChatPerson.fromMap(
              uid, (peopleRaw[uid] as Map?)?.cast<String, dynamic>()),
      },
      listing: ChatListing.fromMap((d['listing'] as Map?)?.cast<String, dynamic>()),
      lastText: d['lastText'] as String? ?? '',
      lastSender: d['lastSender'] as String?,
      updatedAt: _time(d['updatedAt']) ?? _time(d['createdAt']),
      unread: {
        for (final e in ((d['unread'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num?)?.toInt() ?? 0,
      },
      readAt: {
        for (final e in ((d['readAt'] as Map?) ?? const {}).entries)
          if (_time(e.value) != null) '${e.key}': _time(e.value)!,
      },
      typing: {
        for (final e in ((d['typing'] as Map?) ?? const {}).entries)
          '${e.key}': _time(e.value),
      },
    );
  }
}

enum ChatMessageType { text, image }

class ChatMessage {
  final String id;
  final String sender;
  final ChatMessageType type;
  final String text;
  final String? imageUrl;

  /// Server time; falls back to the sender's clock while the write is
  /// still on its way.
  final DateTime sentAt;

  /// Not yet confirmed by the server (shows a clock instead of a tick).
  final bool pending;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.type,
    required this.text,
    required this.sentAt,
    this.imageUrl,
    this.pending = false,
  });

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ChatMessage(
      id: doc.id,
      sender: d['sender'] as String? ?? '',
      type: d['type'] == 'image' ? ChatMessageType.image : ChatMessageType.text,
      text: d['text'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      sentAt: _time(d['createdAt']) ?? _time(d['clientAt']) ?? DateTime.now(),
      pending: doc.metadata.hasPendingWrites,
    );
  }
}

/// Online / last seen for one person.
class Presence {
  final bool online;
  final DateTime? lastSeen;

  const Presence({this.online = false, this.lastSeen});

  static const Presence unknown = Presence();

  /// "Online" only while the app is open and has checked in recently, so a
  /// phone that died without saying goodbye stops showing as online.
  bool get isOnline {
    final seen = lastSeen;
    if (!online || seen == null) return false;
    return DateTime.now().difference(seen).inSeconds < 150;
  }

  /// "Online now", "Last seen 5m ago", "Last seen today at 9:24",
  /// "Last seen yesterday at 18:02", "Last seen 12 Oct".
  String get label {
    if (isOnline) return 'Online now';
    final seen = lastSeen;
    if (seen == null) return '';
    final now = DateTime.now();
    final diff = now.difference(seen);
    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(seen.year, seen.month, seen.day);
    final t = clock(seen);
    if (day == today) return 'Last seen today at $t';
    if (today.difference(day).inDays == 1) return 'Last seen yesterday at $t';
    return 'Last seen ${seen.day} ${_months[seen.month - 1]}';
  }

  factory Presence.fromMap(Map<String, dynamic>? m) => Presence(
        online: m?['online'] as bool? ?? false,
        lastSeen: _time(m?['lastSeen']),
      );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime? _time(Object? v) => switch (v) {
      Timestamp t => t.toDate(),
      DateTime d => d,
      _ => null,
    };

/// "9:24".
String clock(DateTime t) =>
    '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// Inbox time: "now", "2m", "1h", "Tue", "12 Oct".
String inboxTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return _weekdays[t.weekday - 1];
  return '${t.day} ${_months[t.month - 1]}';
}

/// Day separator: "Today", "Yesterday", "Tue 12 Oct".
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}
