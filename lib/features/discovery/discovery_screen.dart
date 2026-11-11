import '../auth/academic_selector.dart';
import '../../widgets/motion_entrance.dart';
import '../../widgets/brand_header.dart';
import '../../theme/app_theme.dart';
import '../../widgets/swipe_card.dart';
import '../../widgets/photo_story.dart';
import '../../widgets/app_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart' show firebaseError;
import '../preferences/discovery_preferences.dart';
import 'discovery_models.dart';
import 'discovery_service.dart';
import 'match_celebration.dart';
import '../chat/chat_screen.dart';
import '../matches/student_match.dart';
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
    this.photoBuilder,
  });
  final String uid;
  final VoidCallback onPreferences, onProfile;
  final DiscoveryService? service;
  final SafetyService? safetyService;
  final Widget Function(String path)? photoBuilder;
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late final _service = widget.service ?? DiscoveryService();
  DiscoveryCandidate? _candidate;
  bool _loading = true, _deciding = false;
  bool _safetyOpen = false, _gestureBusy = false;
  final _cardKey = GlobalKey<SwipeCardState>();
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

  Future<bool> _decide(String type) async {
    if (_deciding || _candidate == null) return false;
    setState(() {
      _deciding = true;
      _error = null;
      _notice = null;
    });
    final target = _candidate!;
    bool advance = false;
    bool matched = false;
    try {
      matched = await _service.decide(widget.uid, target.id, type);
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
        _gestureBusy = false;
        _loading = false;
      });
    }
    if (matched && mounted) {
      final open = await showMatchCelebration(
        context,
        name: target.firstName,
        ownPhoto: _service.ownPhoto,
        otherPhoto: target.mainPhotoUrl,
        photoBuilder: widget.photoBuilder,
      );
      if (open && mounted) {
        await Navigator.of(context).push(
          conversationRoute(
            context,
            (_) => ChatScreen(
              matchId: StudentMatch.idFor(widget.uid, target.id),
              uid: widget.uid,
              profile: target,
            ),
          ),
        );
      }
    }
    return advance;
  }

  Widget _actions() => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _DecisionButton(
          key: const ValueKey('pass-button'),
          label: 'PASAR',
          icon: Icons.close_rounded,
          color: AppColors.danger,
          onPressed: (_deciding || _gestureBusy)
              ? null
              : () => _cardKey.currentState?.decide(false),
        ),
        const SizedBox(width: 38),
        _DecisionButton(
          key: const ValueKey('like-button'),
          label: 'LIKE',
          icon: Icons.favorite_rounded,
          color: AppColors.green,
          onPressed: (_deciding || _gestureBusy)
              ? null
              : () => _cardKey.currentState?.decide(true),
        ),
      ],
    ),
  );
  Widget _deck() => Column(
    children: [
      if (_notice != null) AppNotice(_notice!),
      if (_error != null) AppNotice(_error!, error: true),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('candidate-${_candidate!.id}'),
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: AppMotion.curve,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - v)),
                  child: child,
                ),
              ),
              child: SwipeCard(
                key: _cardKey,
                enabled: !_deciding,
                onBusy: (busy) {
                  if (mounted) setState(() => _gestureBusy = busy);
                },
                onDecision: (like) =>
                    _decide(like ? SwipeDecision.like : SwipeDecision.pass),
                child: CandidateView(
                  candidate: _candidate!,
                  photoBuilder: widget.photoBuilder,
                  careerName:
                      _service.careerNames[_candidate!.careerId] ??
                      'Carrera no disponible',
                  interests: _candidate!.interestIds
                      .where(_service.interestNames.containsKey)
                      .map((id) => _service.interestNames[id]!)
                      .toList(),
                  menu: PopupMenuButton<SafetyAction>(
                    key: const ValueKey('discovery-options'),
                    tooltip: 'Opciones del perfil',
                    iconColor: Colors.white,
                    enabled: !_deciding && !_gestureBusy,
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
              ),
            ),
          ),
        ),
      ),
      _actions(),
      SizedBox(
        height: 3,
        child: _deciding && !_safetyOpen
            ? const LinearProgressIndicator()
            : null,
      ),
    ],
  );
  Widget _status() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Buscando nuevas conexiones…'),
            ] else ...[
              AppEmptyState(
                icon: _error != null
                    ? Icons.person_outline_rounded
                    : Icons.travel_explore_rounded,
                title: _error != null
                    ? 'Antes de continuar'
                    : 'Ya viste los perfiles compatibles',
                message:
                    _error ??
                    'Tus decisiones están guardadas. Prueba otras preferencias o vuelve más tarde para encontrar nuevas conexiones.',
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_error != null)
                    FilledButton.icon(
                      onPressed: widget.onProfile,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Mi perfil'),
                    ),
                  OutlinedButton.icon(
                    onPressed: widget.onPreferences,
                    icon: const Icon(Icons.tune),
                    label: const Text('Preferencias'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar descubrimiento'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const BrandHeader('Descubrir'),
      actions: [
        IconButton(
          onPressed: (_deciding || _gestureBusy) ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Actualizar descubrimiento',
        ),
        IconButton(
          onPressed: (_deciding || _gestureBusy) ? null : widget.onPreferences,
          icon: const Icon(Icons.tune),
          tooltip: 'Preferencias',
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, box) {
          if (_loading || _candidate == null) return _status();
          final compactHeight = box.maxHeight < 450;
          final deck = Padding(
            padding: EdgeInsets.fromLTRB(
              box.maxWidth > 800 ? 24 : 10,
              8,
              box.maxWidth > 800 ? 24 : 10,
              4,
            ),
            child: _deck(),
          );
          if (compactHeight) {
            return SingleChildScrollView(
              child: SizedBox(height: 560, child: deck),
            );
          }
          return deck;
        },
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
    this.photoBuilder,
  });
  final DiscoveryCandidate candidate;
  final String careerName;
  final List<String> interests;
  final Widget? menu;
  final Widget Function(String path)? photoBuilder;
  Widget _details(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${candidate.firstName}, ${candidate.age}',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Icon(Icons.school_outlined, size: 18, color: AppColors.wine),
          const SizedBox(width: 8),
          Expanded(child: Text(careerName)),
        ],
      ),
      const Divider(height: 32),
      const Text(
        'Un poco sobre mí',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      const SizedBox(height: 10),
      Text(
        candidate.description.trim().isEmpty
            ? 'Aún no hay una descripción.'
            : candidate.description,
      ),
      if (interests.isNotEmpty) ...[
        const SizedBox(height: 22),
        const Text(
          'Nos conecta',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 4,
          children: interests
              .map(
                (t) => Chip(
                  label: Text(t),
                  side: BorderSide.none,
                  backgroundColor: AppColors.rose,
                ),
              )
              .toList(),
        ),
      ],
    ],
  );
  void _more(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: _details(ctx),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth > 720;
      final height = box.hasBoundedHeight
          ? box.maxHeight
          : (MediaQuery.sizeOf(context).height * .72).clamp(360.0, 760.0);
      final photos = [
        candidate.mainPhotoUrl,
        ...candidate.photoUrls.where((p) => p != candidate.mainPhotoUrl),
      ].where((p) => p.isNotEmpty).toSet().toList();
      final picture = SizedBox(
        height: height,
        child: PhotoStory(
          photos: photos,
          photoBuilder: photoBuilder,
          allowSwipe: false,
          overlay: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .45, 1],
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xEC17171D),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 20,
                bottom: 26,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '${candidate.firstName}, ${candidate.age}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Información del perfil',
                          onPressed: () => _more(context),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      careerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (candidate.universityId case final university?)
                      AcademicLabel(
                        university: university,
                        campus: candidate.campusId,
                        style: const TextStyle(color: Colors.white),
                      ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: Color(0xFFAEF3DE),
                          size: 14,
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Verificación universitaria aprobada',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (menu != null)
                Positioned(
                  top: 26,
                  right: 12,
                  child: Material(
                    color: Colors.black26,
                    shape: const CircleBorder(),
                    child: menu!,
                  ),
                ),
            ],
          ),
        ),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: AppShadows.card,
        ),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: picture),
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: height,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'UNA CONEXIÓN EMPIEZA AQUÍ',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.6,
                                  color: AppColors.wine,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _details(context),
                              const SizedBox(height: 24),
                              const Text(
                                'Desliza la tarjeta o utiliza los botones para decidir.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : picture,
      );
    },
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
          tooltip: label == 'LIKE' ? 'Me gusta · LIKE' : 'Pasar · PASAR',
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: color,
            disabledBackgroundColor: AppColors.background,
            minimumSize: const Size(64, 64),
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
