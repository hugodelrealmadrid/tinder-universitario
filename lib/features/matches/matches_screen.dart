import 'package:flutter/material.dart';
import '../auth/auth_service.dart' show firebaseError;
import 'matches_service.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, required this.uid, this.service});
  final String uid;
  final MatchesService? service;
  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  late final _service = widget.service ?? MatchesService();
  List<MatchEntry> _entries = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
              : _entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Todavía no tienes matches.'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) =>
                        MatchTile(entry: _entries[index]),
                  ),
                ),
        ),
      ),
    ),
  );
}

class MatchTile extends StatelessWidget {
  const MatchTile({super.key, required this.entry});
  final MatchEntry entry;
  @override
  Widget build(BuildContext context) {
    final profile = entry.profile;
    return Card(
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
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
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
    );
  }
}
