import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/foundation.dart';

import '../models/chat.dart';

/// Real-time chat on Firestore (free Spark plan is enough).
///
/// ```
/// conversations/{id}
///   members   [uidA, uidB]           ← who can read it (see firestore.rules)
///   people    {uid: {name, avatar, verified, agentId}}
///   listing   {id, title, price, image} | null
///   lastText, lastSender, updatedAt
///   unread    {uid: count}           ← inbox badges
///   readAt    {uid: time}            ← blue ticks
///   typing    {uid: bool}            ← "typing…"
/// conversations/{id}/messages/{id}
///   sender, type (text|image), text, imageUrl, createdAt, clientAt
/// presence/{uid}
///   online, lastSeen                 ← "Online now" / "Last seen …"
/// ```
///
/// One conversation per pair of people per listing, so "Home in Palm
/// Jumeirah" and "Marina Gate 2BR" with the same agent stay separate, just
/// like the inbox design.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');

  /// Signed-in Firebase user, or null (signed out / Firebase not set up).
  String? get myUid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Same two people + same listing → same id, from either side.
  static String conversationId(String a, String b, String? listingId) {
    final pair = [a, b]..sort();
    final topic = (listingId == null || listingId.isEmpty) ? 'direct' : listingId;
    return '${pair[0]}_${pair[1]}_$topic';
  }

  // ---------------------------------------------------------------------------
  // Opening a chat
  // ---------------------------------------------------------------------------

  /// Finds or creates the conversation and keeps both name cards fresh.
  /// Returns its id.
  Future<String> open({
    required ChatPerson me,
    required ChatPerson other,
    ChatListing? listing,
  }) async {
    if (me.uid == other.uid) {
      throw const ChatException("You can't message yourself.");
    }
    final id = conversationId(me.uid, other.uid, listing?.id);
    final ref = _conversations.doc(id);
    try {
      final snap = await ref.get();
      if (snap.exists) {
        await ref.update({
          'people.${me.uid}': me.toMap(),
          'people.${other.uid}': other.toMap(),
          if (listing != null) 'listing': listing.toMap(),
        });
      } else {
        await ref.set({
          'members': [me.uid, other.uid],
          'people': {me.uid: me.toMap(), other.uid: other.toMap()},
          'listing': listing?.toMap(),
          'lastText': '',
          'lastSender': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unread': {me.uid: 0, other.uid: 0},
          'readAt': <String, dynamic>{},
          'typing': {me.uid: null, other.uid: null},
        });
      }
    } on FirebaseException catch (e) {
      debugPrint('Chat open failed: ${e.code} ${e.message}');
      throw ChatException(_message(e));
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// My conversations, newest first. Empty ones (opened but never written
  /// in) are hidden from the inbox.
  Stream<List<Conversation>> conversations(String uid) => _conversations
      .where('members', arrayContains: uid)
      .snapshots()
      .map((q) {
        final list = q.docs
            .map(Conversation.fromDoc)
            .where((c) => c.lastSender != null)
            .toList();
        list.sort((a, b) => (b.updatedAt ?? DateTime(2100))
            .compareTo(a.updatedAt ?? DateTime(2100)));
        return list;
      });

  Stream<Conversation?> conversation(String id) => _conversations
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Conversation.fromDoc(s) : null);

  /// Latest [limit] messages, newest first (for a reversed list).
  Stream<List<ChatMessage>> messages(String id, {int limit = 60}) =>
      _conversations
          .doc(id)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots(includeMetadataChanges: true)
          .map((q) => q.docs.map(ChatMessage.fromDoc).toList());

  Stream<Presence> presence(String uid) => _db
      .collection('presence')
      .doc(uid)
      .snapshots()
      .map((s) => Presence.fromMap(s.data()));

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  Future<void> sendText(Conversation c, String me, String text) =>
      _send(c, me, {'type': 'text', 'text': text.trim()}, preview: text.trim());

  Future<void> sendImage(Conversation c, String me, String url,
          {String caption = ''}) =>
      _send(c, me, {'type': 'image', 'imageUrl': url, 'text': caption},
          preview: caption.isEmpty ? '📷 Photo' : '📷 $caption');

  Future<void> _send(Conversation c, String me, Map<String, dynamic> body,
      {required String preview}) async {
    final other = c.otherUid(me);
    final ref = _conversations.doc(c.id);
    final batch = _db.batch()
      ..set(ref.collection('messages').doc(), {
        ...body,
        'sender': me,
        'createdAt': FieldValue.serverTimestamp(),
        'clientAt': Timestamp.now(),
      })
      ..update(ref, {
        'lastText': preview.length > 140 ? '${preview.substring(0, 140)}…' : preview,
        'lastSender': me,
        'updatedAt': FieldValue.serverTimestamp(),
        'unread.$other': FieldValue.increment(1),
        'unread.$me': 0,
        'readAt.$me': FieldValue.serverTimestamp(),
        'typing.$me': null,
      });
    try {
      // Not awaited for the server: the message shows at once (with a
      // clock) and gets its tick when the server confirms. Offline sends
      // go out when the phone reconnects.
      unawaited(batch.commit().catchError((Object e) {
        debugPrint('Chat send failed: $e');
      }));
    } on FirebaseException catch (e) {
      throw ChatException(_message(e));
    }
  }

  /// I've seen everything up to now: clears my badge, turns the sender's
  /// ticks blue.
  Future<void> markRead(String conversationId, String me) async {
    try {
      await _conversations.doc(conversationId).update({
        'unread.$me': 0,
        'readAt.$me': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('markRead failed: $e');
    }
  }

  /// Call with true every few seconds while typing, false when stopped.
  Future<void> setTyping(String conversationId, String me, bool typing) async {
    try {
      await _conversations.doc(conversationId).update(
          {'typing.$me': typing ? FieldValue.serverTimestamp() : null});
    } catch (_) {
      // Typing is best-effort.
    }
  }

  static String _message(FirebaseException e) => switch (e.code) {
        'permission-denied' =>
          "Chat isn't set up on the server yet (Firestore rules).",
        'unavailable' => "You're offline. Messages will send when you reconnect.",
        _ => "Couldn't reach chat. Try again.",
      };
}

class ChatException implements Exception {
  final String message;
  const ChatException(this.message);
  @override
  String toString() => message;
}

/// Total unread messages for the signed-in user — the badge on the Chats
/// tab. Follows sign-in / sign-out on its own.
class ChatUnread extends ValueNotifier<int> {
  ChatUnread._() : super(0);
  static final ChatUnread instance = ChatUnread._();

  StreamSubscription<List<Conversation>>? _sub;
  String? _uid;

  /// Call whenever the signed-in user may have changed.
  void follow(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _sub?.cancel();
    _sub = null;
    if (uid == null) {
      value = 0;
      return;
    }
    try {
      _sub = ChatService.instance.conversations(uid).listen(
        (list) => value = list.fold(0, (n, c) => n + c.unreadFor(uid)),
        onError: (Object e) => debugPrint('Unread stream: $e'),
      );
    } catch (e) {
      debugPrint('Unread stream unavailable: $e');
    }
  }
}
