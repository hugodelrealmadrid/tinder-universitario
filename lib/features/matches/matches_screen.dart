import 'package:flutter/material.dart';
import 'dart:async';
import '../auth/auth_service.dart' show firebaseError;
import 'matches_service.dart';
import 'student_match.dart';
import '../chat/chat_screen.dart';
import '../chat/chat_service.dart';
import 'unmatch_service.dart';

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
      title: const Text('Mis Matches'),
      actions: [
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
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Todavía no tienes matches.'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _visible.length,
                    itemBuilder: (context, index) {
                      final entry = _visible[index];
                      return MatchTile(
                        entry: entry,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => ChatScreen(
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
    final profile = entry.profile;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 90,
                child: profile == null
                    ? const Icon(Icons.person_outline, size: 48)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          profile.mainPhotoUrl,
                          fit: BoxFit.cover,
                          webHtmlElementStrategy:
                              WebHtmlElementStrategy.fallback,
                          errorBuilder: (context, error, stack) =>
                              const Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile == null
                          ? 'Perfil no disponible'
                          : '${profile.firstName}, ${profile.age}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      profile == null
                          ? 'Este match se conserva.'
                          : entry.careerName ?? 'Carrera no disponible',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
