import '../notifications/notifications.dart';
import '../../widgets/motion_entrance.dart';
import '../../widgets/brand_header.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../auth/auth_service.dart' show firebaseError;
import 'matches_service.dart';
import 'student_match.dart';
import '../chat/chat_screen.dart';
import '../chat/chat_service.dart';
import 'unmatch_service.dart';
import 'match_profile_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.uid,
    this.service,
    this.chatService,
    this.unmatchService,
  });
  final String uid;
  final MatchesService? service;
  final ChatService? chatService;
  final UnmatchService? unmatchService;
  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  late final _service = widget.service ?? MatchesService();
  List<MatchEntry> _entries = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Set<String>>? _activeSubscription;
  Set<String>? _activeIds;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _watchActive() {
    _activeSubscription?.cancel();
    _activeIds = null;
    _activeSubscription = _service
        .watchActiveIds(widget.uid)
        .listen(
          (ids) {
            if (mounted) setState(() => _activeIds = ids);
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _activeIds = {};
                _error = firebaseError(error);
              });
            }
          },
        );
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    super.dispose();
  }

  List<MatchEntry> get _visible => _entries
      .where(
        (entry) =>
            _activeIds == null ||
            _activeIds!.contains(
              StudentMatch.idFor(entry.match.users[0], entry.match.users[1]),
            ),
      )
      .toList();

  Future<void> _load() async {
    _watchActive();
    setState(() {
      _loading = true;
      _error = null;
      _entries = [];
    });
    try {
      final entries = await _service.load(widget.uid);
      if (mounted) setState(() => _entries = entries);
    } catch (error) {
      if (mounted) setState(() => _error = firebaseError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const BrandHeader('Mis Matches'),
      actions: [
        const NotificationBell(),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar matches',
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _visible.isEmpty
              ? const AppEmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: 'Todavía no tienes matches.',
                  message:
                      'Las conexiones empiezan con un me gusta. Explora Descubrir y encuentra personas con quienes conectar.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _visible.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Una conexión, muchas posibilidades.',
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.7,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'TUS CONEXIONES',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 116,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _visible.length,
                                separatorBuilder: (_, i) =>
                                    const SizedBox(width: 18),
                                itemBuilder: (context, i) {
                                  final e = _visible[i];
                                  return InkWell(
                                    onTap: e.profile == null
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  MatchProfileScreen(
                                                    viewer: widget.uid,
                                                    target: e.profile!.id,
                                                  ),
                                            ),
                                          ),
                                    child: SizedBox(
                                      width: 76,
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: AppColors.coral,
                                                width: 2,
                                              ),
                                            ),
                                            child: SizedBox(
                                              width: 64,
                                              height: 64,
                                              child: ClipOval(
                                                child: AppPhoto(
                                                  url: e.profile?.mainPhotoUrl,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            e.profile?.firstName ?? 'Perfil',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SectionHeading(
                              'Conversaciones',
                              icon: Icons.chat_bubble_outline,
                            ),
                          ],
                        );
                      }
                      final entry = _visible[index - 1];
                      return MatchTile(
                        entry: entry,
                        onTap: () async {
                          await Navigator.of(context).push(
                            conversationRoute(
                              context,
                              (_) => ChatScreen(
                                matchId: StudentMatch.idFor(
                                  widget.uid,
                                  entry.match.otherUser(widget.uid),
                                ),
                                uid: widget.uid,
                                profile: entry.profile,
                                service: widget.chatService,
                                unmatchService: widget.unmatchService,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      );
                    },
                  ),
                ),
        ),
      ),
    ),
  );
}

class MatchTile extends StatelessWidget {
  const MatchTile({super.key, required this.entry, this.onTap});
  final MatchEntry entry;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = entry.profile;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: ClipOval(child: AppPhoto(url: p?.mainPhotoUrl)),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p == null
                          ? 'Perfil no disponible'
                          : '${p.firstName}, ${p.age}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.careerName ?? 'Este match se conserva.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (p != null)
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MatchProfileScreen(
                                  viewer: entry.match.otherUser(p.id),
                                  target: p.id,
                                ),
                              ),
                            ),
                            child: const Text('Ver perfil'),
                          ),
                        TextButton.icon(
                          onPressed: onTap,
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                          ),
                          label: const Text('Abrir chat'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
