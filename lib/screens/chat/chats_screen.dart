import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/chat_service.dart';
import '../../models/chat.dart';
import '../../state/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home_nav_bar.dart';
import '../../widgets/sign_in_prompt.dart';
import '../../widgets/state_views.dart';
import 'chat_screen.dart';
import 'chat_widgets.dart';

enum _InboxFilter { all, unread, opened }

/// The Chats tab — every conversation, newest first, live.
class ChatsScreen extends StatefulWidget {
  final ValueChanged<NavTab> onNavTap;

  const ChatsScreen({super.key, required this.onNavTap});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with AutomaticKeepAliveClientMixin {
  _InboxFilter _filter = _InboxFilter.all;
  bool _searching = false;
  final TextEditingController _search = TextEditingController();

  Stream<List<Conversation>>? _stream;
  String? _streamUid;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Stream<List<Conversation>> _streamFor(String uid) {
    if (_streamUid != uid || _stream == null) {
      _streamUid = uid;
      _stream = ChatService.instance.conversations(uid);
    }
    return _stream!;
  }

  List<Conversation> _visible(List<Conversation> all, String me) {
    var list = switch (_filter) {
      _InboxFilter.all => all,
      _InboxFilter.unread => all.where((c) => c.unreadFor(me) > 0).toList(),
      _InboxFilter.opened => all.where((c) => c.unreadFor(me) == 0).toList(),
    };
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        final hay = '${c.other(me).name} ${c.listing?.title ?? ''} ${c.lastText}'
            .toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = AppScope.authOf(context);
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final uid = auth.isSignedIn ? ChatService.instance.myUid : null;
            if (uid == null) return _SignedOut(signedIn: auth.isSignedIn);
            return StreamBuilder<List<Conversation>>(
              stream: _streamFor(uid),
              builder: (context, snap) {
                final all = snap.data ?? const <Conversation>[];
                final unreadChats = all.where((c) => c.unreadFor(uid) > 0).length;
                final list = _visible(all, uid);
                return CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(child: _header()),
                    SliverToBoxAdapter(
                      child: _filters(unreadChats),
                    ),
                    if (snap.hasError && all.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _Message(
                          icon: Icons.cloud_off_rounded,
                          title: "Couldn't load chats",
                          body: 'Check your connection and try again.',
                        ),
                      )
                    else if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData)
                      SliverList.separated(
                        itemCount: 3,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (_, _) => const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: SkeletonBox(height: 104, radius: 26),
                        ),
                      )
                    else if (list.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: all.isEmpty
                            ? const _Message(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: 'No chats yet',
                                body: 'Tap Chat on any listing or agent '
                                    'profile to start a conversation.',
                              )
                            : _Message(
                                icon: Icons.search_rounded,
                                title: _search.text.trim().isNotEmpty
                                    ? 'No matches'
                                    : _filter == _InboxFilter.unread
                                        ? "You're all caught up"
                                        : 'Nothing here',
                                body: _search.text.trim().isNotEmpty
                                    ? 'Try a different name or listing.'
                                    : 'New messages will show up here.',
                              ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, i) => _ConversationCard(
                            key: ValueKey(list[i].id),
                            conversation: list[i],
                            me: uid,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ChatScreen(conversationId: list[i].id),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                          height: HomeNavBar.reservedSpace(context) + 20),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 20, 22),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _searching
                    ? Container(
                        key: const ValueKey('search'),
                        height: 52,
                        padding: const EdgeInsets.only(left: 18, right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          style: AppTextStyles.body().copyWith(fontSize: 16),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search chats',
                            hintStyle: AppTextStyles.body(
                                color: AppColors.inkMuted),
                          ),
                        ),
                      )
                    : Align(
                        key: const ValueKey('title'),
                        alignment: Alignment.centerLeft,
                        child: Text('Chats',
                            style: AppTextStyles.display()
                                .copyWith(fontSize: 34, height: 1.1)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _searching = !_searching;
                if (!_searching) _search.clear();
              }),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line),
                ),
                child: Icon(
                  _searching ? Icons.close_rounded : Icons.search_rounded,
                  color: AppColors.ink,
                  size: 25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(int unread) {
    Widget pill(_InboxFilter f, String label, {int? count}) {
      final active = _filter == f;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _filter = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 54,
          padding: EdgeInsets.symmetric(horizontal: f == _InboxFilter.all ? 22 : 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.navDark : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: active ? AppColors.navDark : AppColors.line),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: label),
              if (count != null && count > 0)
                TextSpan(
                  text: ' $count',
                  style: const TextStyle(
                      color: AppColors.amber, fontWeight: FontWeight.w700),
                ),
            ]),
            style: AppTextStyles.body(
                    color: active ? Colors.white : AppColors.ink)
                .copyWith(
                    fontSize: 16.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 20, 20),
      child: Row(
        children: [
          pill(_InboxFilter.all, 'All'),
          const SizedBox(width: 10),
          pill(_InboxFilter.unread, 'Unread', count: unread),
          const SizedBox(width: 10),
          pill(_InboxFilter.opened, 'Opened'),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final Conversation conversation;
  final String me;
  final VoidCallback onTap;

  const _ConversationCard({
    super.key,
    required this.conversation,
    required this.me,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final other = c.other(me);
    final unread = c.unreadFor(me);
    final hasUnread = unread > 0;
    final typingAt = c.typing[other.uid];
    final typing = typingAt != null &&
        DateTime.now().difference(typingAt).inSeconds.abs() < 12;
    final mine = c.lastSender == me;
    final listingLine = c.listing == null
        ? null
        : [c.listing!.title, if (c.listing!.priceLabel.isNotEmpty) c.listing!.priceLabel]
            .join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(26),
          boxShadow: softCardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<Presence>(
              stream: ChatService.instance.presence(other.uid),
              builder: (context, snap) => ChatAvatar(
                url: other.avatarUrl,
                initials: other.initials,
                size: 58,
                online: snap.data?.isOnline ?? false,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          other.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h2()
                              .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        inboxTime(c.updatedAt),
                        style: AppTextStyles.caption(
                                color: hasUnread
                                    ? AppColors.primary
                                    : AppColors.inkMuted)
                            .copyWith(
                                fontSize: 14,
                                fontWeight:
                                    hasUnread ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ],
                  ),
                  if (listingLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      listingLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: const Color(0xFF8E9AA0))
                          .copyWith(fontSize: 15),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: typing
                            ? Text('typing…',
                                style: AppTextStyles.body(
                                        color: AppColors.primary)
                                    .copyWith(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600))
                            : Text(
                                mine ? 'You: ${c.lastText}' : c.lastText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body(
                                        color: hasUnread || mine
                                            ? AppColors.ink
                                            : const Color(0xFF8E9AA0))
                                    .copyWith(
                                        fontSize: 15.5,
                                        height: 1.35,
                                        fontWeight: hasUnread
                                            ? FontWeight.w600
                                            : FontWeight.w400),
                              ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 10),
                        Container(
                          constraints: const BoxConstraints(minWidth: 26),
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: AppTextStyles.caption(color: Colors.white)
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h2().copyWith(fontSize: 20)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

/// Chats need an account.
class _SignedOut extends StatelessWidget {
  final bool signedIn;
  const _SignedOut({required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 20, 0),
          child: Text('Chats',
              style: AppTextStyles.display().copyWith(fontSize: 34, height: 1.1)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    NavIcons.chats,
                    width: 34,
                    height: 34,
                    colorFilter: const ColorFilter.mode(
                        AppColors.primary, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  signedIn ? 'Chat needs an online account' : 'Sign in to chat',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h1(),
                ),
                const SizedBox(height: 8),
                Text(
                  signedIn
                      ? 'Sign out and back in with email or Google to use chat.'
                      : 'Message agents and owners, and keep every '
                          'conversation in one place.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(color: AppColors.inkMuted),
                ),
                if (!signedIn) ...[
                  const SizedBox(height: 24),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => SignInPrompt.gate(
                      context,
                      title: 'Sign in to chat',
                      message: 'Create a free account to message agents and '
                          'owners.',
                      icon: NavIcons.chats,
                      action: () {},
                    ),
                    child: Container(
                      height: 56,
                      width: 220,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: tealGlow(0.8),
                      ),
                      child: Text('Sign in',
                          style: AppTextStyles.bodyStrong(color: Colors.white)
                              .copyWith(fontSize: 17)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
