import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/chat_service.dart';
import '../../data/listing_repository.dart';
import '../../models/chat.dart';
import '../../models/property.dart';
import '../../state/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/media_picker.dart';
import '../property_detail_screen.dart';
import 'chat_launcher.dart';
import 'chat_widgets.dart';

/// One conversation — live messages, read ticks, typing, online status.
class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatService _chat = ChatService.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  late final String _me = _chat.myUid ?? '';

  StreamSubscription<Conversation?>? _convSub;
  Conversation? _conv;
  bool _missing = false;

  int _limit = 60;
  late Stream<List<ChatMessage>> _messages =
      _chat.messages(widget.conversationId, limit: _limit);

  // Typing — mine.
  bool _iAmTyping = false;
  Timer? _typingIdle;
  Timer? _typingRefresh;

  // Typing — theirs. Shown when their stamp changes; hidden 7s after the
  // last change (they refresh every 4s while typing).
  DateTime? _theirTypingStamp;
  bool _theyType = false;
  Timer? _theirTypingTimer;

  bool _foreground = true;
  bool _uploading = false;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _convSub = _chat.conversation(widget.conversationId).listen(
      _onConversation,
      onError: (Object e) => debugPrint('Conversation stream: $e'),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _convSub?.cancel();
    _typingIdle?.cancel();
    _typingRefresh?.cancel();
    _theirTypingTimer?.cancel();
    if (_iAmTyping) _chat.setTyping(widget.conversationId, _me, false);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && (_conv?.unreadFor(_me) ?? 0) > 0) {
      _chat.markRead(widget.conversationId, _me);
    }
    if (!_foreground) _stopTyping();
  }

  void _onConversation(Conversation? c) {
    if (!mounted) return;
    if (c == null) {
      setState(() => _missing = true);
      return;
    }
    // Their typing.
    final other = c.otherUid(_me);
    final stamp = c.typing[other];
    if (stamp == null) {
      _theirTypingTimer?.cancel();
      _theyType = false;
    } else if (stamp != _theirTypingStamp) {
      _theyType = true;
      _theirTypingTimer?.cancel();
      _theirTypingTimer = Timer(const Duration(seconds: 7), () {
        if (mounted) setState(() => _theyType = false);
      });
    }
    _theirTypingStamp = stamp;

    setState(() {
      _conv = c;
      _missing = false;
    });

    // I'm looking at it: clear my badge and turn their ticks blue.
    if (_foreground && c.unreadFor(_me) > 0) {
      _chat.markRead(widget.conversationId, _me);
    }
  }

  void _onScroll() {
    // Reversed list: the top (older messages) is maxScrollExtent.
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
      setState(() {
        _limit += 60;
        _messages = _chat.messages(widget.conversationId, limit: _limit);
      });
      _scroll.removeListener(_onScroll);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _scroll.addListener(_onScroll);
      });
    }
  }

  // --- Typing ---------------------------------------------------------------

  void _onChanged(String text) {
    setState(() {}); // send button state
    if (text.trim().isEmpty) {
      _stopTyping();
      return;
    }
    if (!_iAmTyping) {
      _iAmTyping = true;
      _chat.setTyping(widget.conversationId, _me, true);
      _typingRefresh?.cancel();
      _typingRefresh = Timer.periodic(const Duration(seconds: 4), (_) {
        if (_iAmTyping) _chat.setTyping(widget.conversationId, _me, true);
      });
    }
    _typingIdle?.cancel();
    _typingIdle = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingIdle?.cancel();
    _typingRefresh?.cancel();
    if (!_iAmTyping) return;
    _iAmTyping = false;
    _chat.setTyping(widget.conversationId, _me, false);
  }

  // --- Sending --------------------------------------------------------------

  void _send() {
    final c = _conv;
    final text = _input.text.trim();
    if (c == null || text.isEmpty) return;
    _typingIdle?.cancel();
    _typingRefresh?.cancel();
    _iAmTyping = false; // the send clears it on the server
    _input.clear();
    setState(() {});
    _chat.sendText(c, _me, text);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _attach() async {
    final c = _conv;
    if (c == null || _uploading) return;
    _focus.unfocus();
    final file = await MediaPicker.photo(context, preferFront: false);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final doc = await AppScope.repositoryOf(context).uploadListingFile(
        kind: ListingFileKind.photo,
        bytes: file.bytes,
        fileName: file.name,
        contentType: file.mimeType,
      );
      final url = doc.remoteUrl;
      if (url == null) throw const ChatException("Couldn't send the photo.");
      await _chat.sendImage(c, _me, url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(e is ChatException
                ? e.message
                : "Couldn't send the photo. Try again."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.navDark,
          ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openProfile(ChatPerson other) {
    final id = other.agentId;
    if (id == null) return;
    openAgentProfile(
      context,
      Agent(
        id: id,
        name: other.name,
        agency: '',
        avatarUrl: other.avatarUrl,
        verified: other.verified,
      ),
    );
  }

  void _openListing(ChatListing l) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PropertyDetailScreen(propertyId: l.id)),
      );

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _conv;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _Header(
            conversation: c,
            me: _me,
            theyType: _theyType,
            onBack: () => Navigator.of(context).maybePop(),
            onProfile: c == null ? null : () => _openProfile(c.other(_me)),
            onCall: () => showCallsComingSoon(context),
          ),
          if (c != null && c.listing != null)
            _ListingStrip(
              listing: c.listing!,
              onTap: () => _openListing(c.listing!),
            ),
          Expanded(
            child: _missing
                ? Center(
                    child: Text('This chat is no longer available.',
                        style: AppTextStyles.body(color: AppColors.inkMuted)),
                  )
                : GestureDetector(
                    onTap: () => _focus.unfocus(),
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: _messages,
                      builder: (context, snap) {
                        final msgs = snap.data ?? const <ChatMessage>[];
                        if (!snap.hasData) {
                          return const Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primary),
                              ),
                            ),
                          );
                        }
                        return _buildMessages(msgs, c);
                      },
                    ),
                  ),
          ),
          _Composer(
            controller: _input,
            focus: _focus,
            uploading: _uploading,
            canSend: _input.text.trim().isNotEmpty && c != null,
            onChanged: _onChanged,
            onSend: _send,
            onAttach: _attach,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(List<ChatMessage> msgs, Conversation? c) {
    if (msgs.isEmpty && !_theyType) {
      final other = c?.other(_me);
      return ListView(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        children: [
          Column(
            children: [
              Text(
                other == null ? 'Say hello' : 'Say hello to ${other.name.split(' ').first}',
                textAlign: TextAlign.center,
                style: AppTextStyles.h2(),
              ),
              const SizedBox(height: 6),
              Text(
                c?.listing == null
                    ? 'Ask anything — they usually reply quickly.'
                    : 'Ask about availability, viewings or the price.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in const [
                    'Hi! Is this still available?',
                    'Can I book a viewing?',
                    'Is the price negotiable?',
                  ])
                    GestureDetector(
                      onTap: () {
                        _input.text = q;
                        _input.selection =
                            TextSelection.collapsed(offset: q.length);
                        _onChanged(q);
                        _focus.requestFocus();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Text(q,
                            style: AppTextStyles.caption(color: AppColors.ink)
                                .copyWith(fontSize: 14)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      );
    }

    // When did they last read? Everything of mine sent before that is read.
    final theirRead = c == null ? null : c.readAt[c.otherUid(_me)];
    final latestMineId = msgs.where((m) => m.sender == _me).firstOrNull?.id;

    final items = <Widget>[];
    if (_theyType) items.add(const _TypingBubble());
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final mine = m.sender == _me;
      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
      final newer = i > 0 ? msgs[i - 1] : null;
      final read = mine && theirRead != null && !m.pending &&
          !m.sentAt.isAfter(theirRead.add(const Duration(seconds: 1)));
      final showStatus = mine && (m.id == latestMineId || _expandedId == m.id);
      final showTime = !mine && _expandedId == m.id;
      final groupedWithNewer = newer != null &&
          newer.sender == m.sender &&
          newer.sentAt.difference(m.sentAt).inMinutes < 3;

      items.add(Padding(
        padding: EdgeInsets.only(
            bottom: showStatus || showTime ? 14 : (groupedWithNewer ? 6 : 14)),
        child: _Bubble(
          message: m,
          mine: mine,
          read: read,
          showStatus: showStatus,
          showTime: showTime,
          onTap: () => setState(
              () => _expandedId = _expandedId == m.id ? null : m.id),
        ),
      ));

      // Day pill above the first message of each day.
      if (older == null || !_sameDay(older.sentAt, m.sentAt)) {
        items.add(_DayPill(label: dayLabel(m.sentAt)));
      }
    }

    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      children: items,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Header extends StatelessWidget {
  final Conversation? conversation;
  final String me;
  final bool theyType;
  final VoidCallback onBack;
  final VoidCallback? onProfile;
  final VoidCallback onCall;

  const _Header({
    required this.conversation,
    required this.me,
    required this.theyType,
    required this.onBack,
    required this.onProfile,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final other = c?.other(me);
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.paddingOf(context).top + 10, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EEEF))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.ink, size: 26),
          ),
          Expanded(
            child: other == null
                ? const SizedBox(height: 54)
                : StreamBuilder<Presence>(
                    stream: ChatService.instance.presence(other.uid),
                    builder: (context, snap) {
                      final p = snap.data ?? Presence.unknown;
                      final status = theyType ? 'typing…' : p.label;
                      final statusColor = theyType
                          ? AppColors.primary
                          : p.isOnline
                              ? AppColors.success
                              : AppColors.inkMuted;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: other.agentId == null ? null : onProfile,
                        child: Row(
                          children: [
                            ChatAvatar(
                              url: other.avatarUrl,
                              initials: other.initials,
                              size: 52,
                              online: p.isOnline,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          other.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.h2().copyWith(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      if (other.verified) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.verified_rounded,
                                            color: AppColors.amber, size: 20),
                                      ],
                                    ],
                                  ),
                                  if (status.isNotEmpty)
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      child: Text(
                                        status,
                                        key: ValueKey(status),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body(
                                                color: statusColor)
                                            .copyWith(
                                                fontSize: 15,
                                                fontWeight: theyType ||
                                                        p.isOnline
                                                    ? FontWeight.w600
                                                    : FontWeight.w400),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCall,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
              child: const Icon(Icons.call_outlined,
                  color: AppColors.ink, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

/// The listing this chat is about — slim and tappable.
class _ListingStrip extends StatelessWidget {
  final ChatListing listing;
  final VoidCallback onTap;

  const _ListingStrip({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: Color(0xFFE8EEEF))),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 40,
                height: 40,
                child: listing.imageUrl == null
                    ? Container(
                        color: AppColors.primaryTint,
                        child: const Icon(Icons.home_rounded,
                            color: AppColors.primary, size: 20),
                      )
                    : Image.network(listing.imageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                        errorBuilder: (_, _, _) =>
                            Container(color: AppColors.primaryTint)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: listing.title,
                      style: AppTextStyles.bodyStrong().copyWith(fontSize: 14.5)),
                  if (listing.priceLabel.isNotEmpty)
                    TextSpan(
                        text: '  ·  ${listing.priceLabel}',
                        style: AppTextStyles.caption().copyWith(fontSize: 14)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  final String label;
  const _DayPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 18),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EDEE),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: AppTextStyles.caption().copyWith(
                  fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool read;
  final bool showStatus;
  final bool showTime;
  final VoidCallback onTap;

  const _Bubble({
    required this.message,
    required this.mine,
    required this.read,
    required this.showStatus,
    required this.showTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = message;
    final maxW = MediaQuery.sizeOf(context).width * 0.76;
    const r = Radius.circular(24);
    const small = Radius.circular(8);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: mine ? r : small,
      bottomRight: mine ? small : r,
    );

    final Widget content = m.type == ChatMessageType.image && m.imageUrl != null
        ? GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PhotoViewer(url: m.imageUrl!),
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Image.network(
                m.imageUrl!,
                width: maxW * 0.85,
                height: maxW * 0.85,
                fit: BoxFit.cover,
                cacheWidth: 700,
                loadingBuilder: (c, child, progress) => progress == null
                    ? child
                    : Container(
                        width: maxW * 0.85,
                        height: maxW * 0.85,
                        color: const Color(0xFFE8EDEE),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => Container(
                  width: maxW * 0.85,
                  height: 120,
                  color: const Color(0xFFE8EDEE),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: AppColors.inkMuted),
                ),
              ),
            ),
          )
        : Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.surface,
              borderRadius: radius,
              boxShadow: mine ? tealGlow(0.55) : softCardShadow,
            ),
            child: Text(
              m.text,
              style: AppTextStyles.body(
                      color: mine ? Colors.white : AppColors.ink)
                  .copyWith(fontSize: 16.5, height: 1.5),
            ),
          );

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: content,
          ),
        ),
        if (showStatus) ...[
          const SizedBox(height: 8),
          _Status(message: m, read: read),
        ] else if (showTime) ...[
          const SizedBox(height: 6),
          Text(clock(m.sentAt),
              style: AppTextStyles.caption().copyWith(fontSize: 13)),
        ],
      ],
    );
  }
}

/// "Read · 9:24 ✓✓" (teal), "Sent · 9:24 ✓" (grey), "Sending…" (clock).
class _Status extends StatelessWidget {
  final ChatMessage message;
  final bool read;

  const _Status({required this.message, required this.read});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final style = AppTextStyles.caption(color: const Color(0xFF8E9AA0))
        .copyWith(fontSize: 13.5);
    if (m.pending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sending', style: style),
          const SizedBox(width: 6),
          const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFF8E9AA0)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${read ? 'Read' : 'Sent'} · ${clock(m.sentAt)}', style: style),
        const SizedBox(width: 6),
        Icon(
          read ? Icons.done_all_rounded : Icons.done_rounded,
          size: 17,
          color: read ? AppColors.primary : const Color(0xFF8E9AA0),
        ),
      ],
    );
  }
}

/// Three bouncing dots while the other person types.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
              bottomLeft: Radius.circular(8),
            ),
            boxShadow: softCardShadow,
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Transform.translate(
                    offset: Offset(0, _lift(i)),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: 0.45 + 0.55 * (-_lift(i) / 4)),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 0 … -4 px, staggered per dot.
  double _lift(int i) {
    final t = (_c.value - i * 0.18) % 1.0;
    if (t > 0.5) return 0;
    final x = t / 0.5; // 0→1
    return -4 * (1 - (2 * x - 1) * (2 * x - 1));
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool uploading;
  final bool canSend;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  const _Composer({
    required this.controller,
    required this.focus,
    required this.uploading,
    required this.canSend,
    required this.onChanged,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottom + 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0xFFE8EEEF))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: uploading ? null : onAttach,
            child: Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2F3),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    )
                  : const Icon(Icons.add_rounded,
                      color: AppColors.inkMuted, size: 28),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2F3),
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: controller,
                focusNode: focus,
                onChanged: onChanged,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                style: AppTextStyles.body().copyWith(fontSize: 16.5),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: InputBorder.none,
                  hintText: 'Type a message...',
                  hintStyle: AppTextStyles.body(color: const Color(0xFF8E9AA0))
                      .copyWith(fontSize: 16.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canSend ? onSend : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: canSend ? tealGlow() : tealGlow(0.35),
              ),
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: -0.55,
                child: const Padding(
                  padding: EdgeInsets.only(left: 3, bottom: 2),
                  child: Icon(Icons.send_outlined, color: Colors.white, size: 25),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final String url;
  const _PhotoViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
