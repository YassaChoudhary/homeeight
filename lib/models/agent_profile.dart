import 'property.dart';

/// The "Agent profile" screen — an agent, company or private owner, with
/// their live listings. From the `agent_profile` RPC (signed-in only).
class AgentProfile {
  final String id;
  final String name;
  final String agency;
  final String? avatarUrl;
  final bool verified;
  final String responseTime;

  /// 'agent' | 'company' | 'individual' | 'agency' (seeded agents).
  final String kind;

  /// Licence / RERA number once verified, else empty.
  final String licence;
  final int memberSince;

  /// The person's Firebase uid — who a chat goes to. Null when they don't
  /// use the app, so chat isn't possible.
  final String? chatUid;

  final int activeCount;
  final int closedCount;
  final List<Property> listings;

  const AgentProfile({
    required this.id,
    required this.name,
    required this.agency,
    this.avatarUrl,
    this.verified = false,
    this.responseTime = '~15 min',
    this.kind = 'agency',
    this.licence = '',
    this.memberSince = 2026,
    this.chatUid,
    this.activeCount = 0,
    this.closedCount = 0,
    this.listings = const [],
  });

  bool get canChat => chatUid != null && chatUid!.isNotEmpty;

  bool get isOwner => kind == 'individual';

  /// "Senior consultant · Haus & Haus Realty" line under the name.
  String get roleLine => switch (kind) {
        'individual' => 'Property owner',
        'company' => agency.isEmpty ? 'Real estate company' : agency,
        _ => agency.isEmpty ? 'Agent' : 'Agent · $agency',
      };

  /// Headline for the screen ("Agent profile" / "Owner profile").
  String get screenTitle => switch (kind) {
        'individual' => 'Owner profile',
        'company' => 'Company profile',
        _ => 'Agent profile',
      };

  Agent toAgent() => Agent(
        id: id,
        name: name,
        agency: agency,
        avatarUrl: avatarUrl,
        verified: verified,
        responseTime: responseTime,
      );

  factory AgentProfile.fromJson(Map<String, dynamic> j) => AgentProfile(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        agency: j['agency_name'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        verified: j['verified'] as bool? ?? false,
        responseTime: j['response_time'] as String? ?? '~15 min',
        kind: j['kind'] as String? ?? 'agency',
        licence: j['licence'] as String? ?? '',
        memberSince: (j['member_since'] as num?)?.toInt() ?? 2026,
        chatUid: j['chat_uid'] as String?,
        activeCount: (j['active_count'] as num?)?.toInt() ?? 0,
        closedCount: (j['closed_count'] as num?)?.toInt() ?? 0,
        listings: [
          for (final e in (j['listings'] as List? ?? const []))
            if (e is Map) Property.fromJson(Map<String, dynamic>.from(e)),
        ],
      );
}
