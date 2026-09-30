import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart' show firebaseError;
import '../preferences/discovery_preferences.dart';
import 'discovery_models.dart';
import 'discovery_service.dart';
import '../safety/safety_dialog.dart';
import '../safety/safety_service.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    required this.uid,
    required this.onPreferences,
    required this.onProfile,
    this.service,
    this.safetyService,
  });
  final String uid;
  final VoidCallback onPreferences, onProfile;
  final DiscoveryService? service;
  final SafetyService? safetyService;
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late final _service = widget.service ?? DiscoveryService();
  DiscoveryCandidate? _candidate;
  bool _loading = true, _deciding = false;
  bool _safetyOpen = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.cancel();
    super.dispose();
  }

  String _message(Object error) =>
      error is DiscoveryException ? error.message : firebaseError(error);

  Future<void> _safety(SafetyAction action) async {
    if (_deciding || _candidate == null) return;
    final target = _candidate!.id;
    setState(() {
      _deciding = true;
      _safetyOpen = true;
    });
    try {
      final done = await showSafetyDialog(
        context,
        target: target,
        action: action,
        service: widget.safetyService,
      );
      if (!mounted || !done) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == SafetyAction.block
                ? 'Usuario bloqueado.'
                : 'Reporte enviado.',
          ),
        ),
      );
      if (action == SafetyAction.block) {
        _service.exclude(target);
        setState(() {
          _candidate = null;
          _loading = true;
          _error = null;
        });
        final next = await _service.next();
        if (mounted) setState(() => _candidate = next);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _deciding = false;
          _safetyOpen = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    if (_deciding) return;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _candidate = null;
    });
    try {
      await _service.start(widget.uid);
      if (!mounted) return;
      final candidate = await _service.next();
      if (mounted) setState(() => _candidate = candidate);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String type) async {
    if (_deciding || _candidate == null) return;
    setState(() {
      _deciding = true;
      _error = null;
      _notice = null;
    });
    bool advance = false;
    try {
      final newMatch = await _service.decide(widget.uid, _candidate!.id, type);
      if (newMatch && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('¡Es un match!')));
      }
      advance = true;
    } catch (error) {
      if (error is DiscoveryException && error.alreadyDecided ||
          error is FirebaseException && error.code == 'permission-denied') {
        advance = true;
        if (mounted) {
          setState(
            () => _notice =
                'El perfil ya fue evaluado o dejó de estar disponible.',
          );
        }
      } else if (mounted) {
        setState(() => _error = _message(error));
      }
    }
    if (advance && mounted) {
      setState(() {
        _candidate = null;
        _loading = true;
      });
      try {
        final next = await _service.next();
        if (mounted) setState(() => _candidate = next);
      } catch (error) {
        if (mounted) setState(() => _error = _message(error));
      }
    }
    if (mounted) {
      setState(() {
        _deciding = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Descubrir'),
      actions: [
        IconButton(
          onPressed: _deciding ? null : widget.onPreferences,
          icon: const Icon(Icons.tune),
          tooltip: 'Preferencias',
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_notice!),
                  ),
                if (!_loading && _candidate != null) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<SafetyAction>(
                      key: const ValueKey('discovery-options'),
                      tooltip: 'Opciones del perfil',
                      enabled: !_deciding,
                      onSelected: _safety,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: SafetyAction.block,
                          child: Text('Bloquear usuario'),
                        ),
                        PopupMenuItem(
                          value: SafetyAction.report,
                          child: Text('Reportar usuario'),
                        ),
                      ],
                    ),
                  ),
                  CandidateView(
                    candidate: _candidate!,
                    careerName:
                        _service.careerNames[_candidate!.careerId] ??
                        'Carrera no disponible',
                    interests: _candidate!.interestIds
                        .where(_service.interestNames.containsKey)
                        .map((id) => _service.interestNames[id]!)
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('pass-button'),
                          onPressed: _deciding
                              ? null
                              : () => _decide(SwipeDecision.pass),
                          icon: const Icon(Icons.close),
                          label: const Text('PASS'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('like-button'),
                          onPressed: _deciding
                              ? null
                              : () => _decide(SwipeDecision.like),
                          icon: const Icon(Icons.favorite),
                          label: const Text('LIKE'),
                        ),
                      ),
                    ],
                  ),
                  if (_deciding && !_safetyOpen)
                    const LinearProgressIndicator(),
                ],
                if (!_loading && _candidate == null && _error == null) ...[
                  const Icon(Icons.people_outline, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay más perfiles compatibles por ahora.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Puedes revisar tus preferencias o volver más tarde. Las decisiones anteriores se conservan.',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                if (!_loading)
                  TextButton.icon(
                    onPressed: _deciding ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar descubrimiento'),
                  ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _deciding ? null : widget.onPreferences,
                      child: const Text('Preferencias'),
                    ),
                    TextButton(
                      onPressed: _deciding ? null : widget.onProfile,
                      child: const Text('Mi perfil'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Recibe solo la ficha reducida. No renderiza UID, email ni fecha exacta.
class CandidateView extends StatelessWidget {
  const CandidateView({
    super.key,
    required this.candidate,
    required this.careerName,
    required this.interests,
  });
  final DiscoveryCandidate candidate;
  final String careerName;
  final List<String> interests;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: Image.network(
            candidate.mainPhotoUrl,
            fit: BoxFit.cover,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (context, error, stack) => const Center(
              child: Icon(Icons.image_not_supported_outlined, size: 64),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${candidate.firstName}, ${candidate.age}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(careerName),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: interests
                    .map((name) => Chip(label: Text(name)))
                    .toList(),
              ),
              if (candidate.description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(candidate.description),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
