import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
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
    bottomNavigationBar: !_loading && _candidate != null
        ? SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DecisionButton(
                        key: const ValueKey('pass-button'),
                        label: 'PASS',
                        icon: Icons.close_rounded,
                        color: AppColors.danger,
                        onPressed: _deciding
                            ? null
                            : () => _decide(SwipeDecision.pass),
                      ),
                      const SizedBox(width: 40),
                      _DecisionButton(
                        key: const ValueKey('like-button'),
                        label: 'LIKE',
                        icon: Icons.favorite_rounded,
                        color: AppColors.green,
                        onPressed: _deciding
                            ? null
                            : () => _decide(SwipeDecision.like),
                      ),
                    ],
                  ),
                  if (_deciding && !_safetyOpen)
                    const LinearProgressIndicator(),
                ],
              ),
            ),
          )
        : null,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
                if (_error != null) AppNotice(_error!, error: true),
                if (_notice != null) AppNotice(_notice!),
                if (!_loading && _candidate != null) ...[
                  CandidateView(
                    candidate: _candidate!,
                    menu: PopupMenuButton<SafetyAction>(
                      key: const ValueKey('discovery-options'),
                      tooltip: 'Opciones del perfil',
                      iconColor: Colors.white,
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
                    careerName:
                        _service.careerNames[_candidate!.careerId] ??
                        'Carrera no disponible',
                    interests: _candidate!.interestIds
                        .where(_service.interestNames.containsKey)
                        .map((id) => _service.interestNames[id]!)
                        .toList(),
                  ),
                ],
                if (!_loading && _candidate == null && _error == null) ...[
                  const AppEmptyState(
                    icon: Icons.explore_outlined,
                    title: 'No hay más perfiles compatibles por ahora.',
                    message:
                        'Puedes revisar tus preferencias o volver más tarde. Las decisiones anteriores se conservan.',
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
    this.menu,
  });
  final DiscoveryCandidate candidate;
  final String careerName;
  final List<String> interests;
  final Widget? menu;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Positioned.fill(child: AppPhoto(url: candidate.mainPhotoUrl)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .08),
                      Colors.black.withValues(alpha: .12),
                      Colors.black.withValues(alpha: .9),
                    ],
                    stops: const [0, .35, 1],
                  ),
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 400),
              padding: const EdgeInsets.fromLTRB(22, 230, 22, 24),
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${candidate.firstName}, ${candidate.age}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.school_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          careerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (interests.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: interests
                          .map(
                            (name) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .35),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .4),
                                ),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (menu != null)
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: .35),
                  shape: const CircleBorder(),
                  child: menu!,
                ),
              ),
          ],
        ),
        if (candidate.description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UN POCO SOBRE MÍ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(candidate.description),
              ],
            ),
          ),
      ],
    ),
  );
}

class _DecisionButton extends StatelessWidget {
  const _DecisionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: IconButton.filledTonal(
          tooltip: label == 'LIKE' ? 'Me gusta · LIKE' : 'Pasar · PASS',
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: color,
            disabledBackgroundColor: AppColors.background,
            minimumSize: const Size(72, 72),
            iconSize: 34,
          ),
          icon: Icon(icon),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}
