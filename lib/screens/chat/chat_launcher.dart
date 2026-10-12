import 'package:flutter/material.dart';

import '../../data/chat_service.dart';
import '../../models/agent_profile.dart';
import '../../models/chat.dart';
import '../../models/lister_profile.dart';
import '../../models/property.dart';
import '../../state/app_scope.dart';
import '../../theme/app_colors.dart';
import '../../widgets/home_nav_bar.dart';
import '../../widgets/sign_in_prompt.dart';
import '../agent_profile_screen.dart';
import 'chat_screen.dart';

/// Agent / owner profile — guests are asked to sign in first.
Future<void> openAgentProfile(BuildContext context, Agent agent) {
  return SignInPrompt.gate(
    context,
    title: 'Sign in to view profile',
    message: 'Create a free account to see agents and owners, their '
        'listings, and chat with them.',
    icon: NavIcons.profile,
    action: () {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AgentProfileScreen(agent: agent)),
      );
    },
  );
}

/// Starts (or reopens) a chat with an agent / owner, optionally about one
/// listing. Signs the user in first if needed.
Future<void> startChat(
  BuildContext context, {
  required String agentId,
  AgentProfile? profile,
  Property? listing,
}) {
  return SignInPrompt.gate(
    context,
    title: 'Sign in to chat',
    message: 'Create a free account to message agents and owners, and get '
        'replies right here.',
    icon: NavIcons.chats,
    action: () {
      if (!context.mounted) return;
      _start(context, agentId: agentId, profile: profile, listing: listing);
    },
  );
}

Future<void> _start(
  BuildContext context, {
  required String agentId,
  AgentProfile? profile,
  Property? listing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final auth = AppScope.authOf(context);
  final repo = AppScope.repositoryOf(context);

  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navDark,
    ));

  final myUid = ChatService.instance.myUid;
  final user = auth.user;
  if (myUid == null || user == null) {
    say('Please sign in again to use chat.');
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    ),
  );

  String? conversationId;
  String? problem;
  try {
    final agent = profile ?? await repo.agentProfile(agentId);
    if (agent == null || !agent.canChat) {
      problem = "This agent isn't on Home8 chat yet. Try Call or WhatsApp "
          'on the listing.';
    } else if (agent.chatUid == myUid) {
      problem = 'This is your own profile.';
    } else {
      conversationId = await ChatService.instance.open(
        me: ChatPerson(
          uid: myUid,
          name: user.name,
          avatarUrl: user.avatarUrl,
          verified:
              user.listerProfile?.status == VerificationStatus.verified,
        ),
        other: ChatPerson(
          uid: agent.chatUid!,
          name: agent.name,
          avatarUrl: agent.avatarUrl,
          verified: agent.verified,
          agentId: agent.id,
        ),
        listing: listing == null ? null : ChatListing.fromProperty(listing),
      );
    }
  } on ChatException catch (e) {
    problem = e.message;
  } catch (e) {
    debugPrint('Start chat failed: $e');
    problem = "Couldn't open the chat. Check your connection and try again.";
  }
  navigator.pop(); // spinner

  if (problem != null) {
    say(problem);
    return;
  }
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => ChatScreen(conversationId: conversationId!),
    ),
  );
}
