import 'notification_link.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../auth/auth_service.dart';
import '../chat/chat_screen.dart';
import '../discovery/discovery_models.dart';
import '../verification/backend_client.dart';
import '../verification/university_verification_screen.dart';

const ligoNotifications = bool.fromEnvironment('LIGO_NOTIFICATIONS');
const _enablePush = bool.fromEnvironment('LIGO_FCM');
const _vapid = String.fromEnvironment('LIGO_WEB_VAPID');
final _noticeId = RegExp(r'^[a-f0-9]{64}$');

class LigoNotice {
  LigoNotice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc)
    : id = doc.id,
      data = doc.data()!;
  final String id;
  final Map<String, dynamic> data;
  String? get sender => data['sender'] as String?;
  String? get matchId => data['matchId'] as String?;
  bool get unread => data['readAt'] == null;
  DateTime? get date => (data['createdAt'] as Timestamp?)?.toDate();
  bool get isStoryReply => data['kind'] == 'story_reply';
  bool get isVerification => data['kind'] == 'verification';
  String get title => switch (data['kind']) {
    'match' => 'Nuevo match',
    'message' => 'Nuevo mensaje',
    'story_reply' => 'Respuesta a historia',
    'verification' => 'Acreditación universitaria',
    _ => 'Notificación',
  };
  String get description => switch (data['kind']) {
    'match' => 'Hay una nueva conexión.',
    'message' => 'Recibiste un mensaje en el chat.',
    'story_reply' => 'respondió a tu historia',
    'verification' => switch (data['status']) {
      'approved' => 'Tu acreditación fue aprobada.',
      'pending' => 'Tu carnet está pendiente de revisión.',
      _ => 'Tu solicitud fue revisada. Consulta el resultado.',
    },
    _ => 'Consulta tu actividad en LIGO.',
  };
  IconData get icon => switch (data['kind']) {
    'match' => Icons.favorite_border,
    'message' => Icons.chat_bubble_outline,
    'story_reply' => Icons.auto_stories_outlined,
    _ => Icons.verified_user_outlined,
  };
}

class NotificationHub extends StatefulWidget {
  const NotificationHub({
    super.key,
    required this.service,
    required this.uid,
    required this.child,
    this.firestore,
  });
  final AuthService service;
  final String uid;
  final Widget child;
  final FirebaseFirestore? firestore;

  static NotificationHubState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NotificationProvider>()?.hub;

  @override
  State<NotificationHub> createState() => NotificationHubState();
}

class NotificationHubState extends State<NotificationHub> {
  late final db = widget.firestore ?? FirebaseFirestore.instance;
  late final client = VerificationClient(auth: widget.service.auth);
  late final _totals = db.doc('notificationInboxes/${widget.uid}').snapshots();
  late final settings = db
      .doc('notificationSettings/${widget.uid}')
      .snapshots();
  late final inbox = db.collection('notificationInboxes/${widget.uid}/items');
  Query<Map<String, dynamic>> get page =>
      inbox.orderBy('createdAt', descending: true).limit(25);
  late final latest = page.snapshots();
  final _profiles = <String, Future<DiscoveryCandidate?>>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _arrivals;
  StreamSubscription<RemoteMessage>? _opened, _foreground;
  StreamSubscription<String>? _refresh;
  String? _deviceToken;
  bool _sessionInitialized = false, _opening = false, _changingPush = false;
  final _seen = <String>{};
  final DateTime _mountedAt = DateTime.now();

  bool get canPush =>
      _enablePush &&
      !db.app.options.projectId.startsWith('demo-') &&
      (kIsWeb
          ? _vapid.isNotEmpty
          : defaultTargetPlatform == TargetPlatform.android);

  Stream<DocumentSnapshot<Map<String, dynamic>>> get totals => _totals;
  Future<DiscoveryCandidate?> profile(String? sender) {
    if (sender == null) return Future.value();
    return _profiles.putIfAbsent(sender, () async {
      try {
        final row = await db
            .doc('discoveryCards/$sender')
            .get(const GetOptions(source: Source.server));
        return row.exists
            ? DiscoveryCandidate.fromMap(sender, row.data()!)
            : null;
      } catch (_) {
        return null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.service.beforeLogout = _removeDevice;
    _arrivals = latest.listen((page) {
      if (page.metadata.isFromCache) return;
      if (!_sessionInitialized) {
        _seen.addAll(page.docs.map((row) => row.id));
        _sessionInitialized = true;
        return;
      }
      for (final row in page.docs.reversed) {
        _announce(LigoNotice.fromDoc(row));
      }
    }, onError: (Object _) {});
    if (canPush) {
      final messaging = FirebaseMessaging.instance;
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((event) {
        unawaited(openId(event.data['notice']));
      });
      _foreground = FirebaseMessaging.onMessage.listen((event) {
        unawaited(_announcePush(event.data['notice']));
      });
      _refresh = messaging.onTokenRefresh.listen((token) {
        unawaited(_registerIfEnabled(token));
      }, onError: (Object _) {});
      unawaited(_restorePush(messaging));
    }
    if (kIsWeb) {
      final id = consumeNotificationLink();
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(openId(id));
        });
      }
    }
  }

  Future<void> _announcePush(dynamic id) async {
    if (id is! String || !_noticeId.hasMatch(id)) return;
    try {
      final doc = await inbox
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (doc.exists) _announce(LigoNotice.fromDoc(doc));
    } catch (_) {
      // The authenticated Firestore feed is still authoritative.
    }
  }

  void _announce(LigoNotice note) {
    if (!mounted ||
        !note.unread ||
        note.date?.isAfter(_mountedAt) != true ||
        !_seen.add(note.id)) {
      return;
    }
    if (_seen.length > 500) _seen.remove(_seen.first);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(note.title),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () => unawaited(openId(note.id)),
        ),
      ),
    );
  }

  Future<void> _restorePush(FirebaseMessaging messaging) async {
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null && mounted) unawaited(openId(initial.data['notice']));
      final setting = await messaging.getNotificationSettings();
      if (mounted &&
          setting.authorizationStatus == AuthorizationStatus.authorized &&
          (await db.doc('notificationSettings/${widget.uid}').get())
                  .data()?['push'] ==
              true) {
        final token = await messaging.getToken(
          vapidKey: kIsWeb ? _vapid : null,
        );
        if (token != null) await _registerIfEnabled(token);
      }
    } catch (_) {
      /* El buzón permanece disponible. */
    }
  }

  Future<void> _registerIfEnabled(String token) async {
    if (!mounted ||
        _changingPush ||
        widget.service.currentUser?.uid != widget.uid) {
      return;
    }
    try {
      if ((await db.doc('notificationSettings/${widget.uid}').get())
                  .data()?['push'] !=
              true ||
          !mounted ||
          _changingPush ||
          widget.service.currentUser?.uid != widget.uid) {
        return;
      }
      await _registerDevice(token);
    } catch (_) {
      /* El token nunca se registra en logs. */
    }
  }

  Future<void> _registerDevice(String token) async {
    await client.notificationDevice(token, kIsWeb ? 'web' : 'android');
    final old = _deviceToken;
    _deviceToken = token;
    if (old != null && old != token) await client.removeNotificationDevice(old);
  }

  Future<void> _removeDevice() async {
    if (!canPush) return;
    final token = _deviceToken;
    _deviceToken = null;
    if (token != null) {
      try {
        await client
            .removeNotificationDevice(token)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 4),
      );
    } catch (_) {}
  }

  Future<String> changePush(bool enable) async {
    if (!canPush) return 'Push no configurado en este entorno.';
    _changingPush = true;
    try {
      if (!enable) {
        await client.notificationPreferences(false);
        await _removeDevice();
        return 'Alertas push desactivadas.';
      }
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus != AuthorizationStatus.authorized) {
        return 'Permiso denegado. Puedes cambiarlo en los ajustes del dispositivo.';
      }
      final token = await messaging.getToken(vapidKey: kIsWeb ? _vapid : null);
      if (token == null || !mounted) {
        return 'No se pudo registrar este dispositivo.';
      }
      await _registerDevice(token);
      await client.notificationPreferences(true);
      return 'Alertas push habilitadas para la cuenta.';
    } finally {
      _changingPush = false;
    }
  }

  Future<void> openId(dynamic id) async {
    if (id is! String || !_noticeId.hasMatch(id) || _opening || !mounted) {
      return;
    }
    try {
      final doc = await inbox
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (doc.exists && mounted) await open(LigoNotice.fromDoc(doc));
    } catch (_) {
      if (mounted) _message('Esta notificación ya no está disponible.');
    }
  }

  void _message(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));

  Future<void> open(LigoNotice note) async {
    if (_opening || !mounted) return;
    _opening = true;
    try {
      final access = await widget.service.watchAccountAccess(widget.uid).first;
      if (!mounted || access.suspended) return;
      if (note.unread) await client.readNotification(note.id);
      if (!mounted) return;
      if (note.isVerification) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UniversityVerificationScreen(
              client: client,
              access: access,
              logout: const SizedBox.shrink(),
            ),
          ),
        );
      } else if (note.matchId case final String match when access.canDate) {
        final data =
            (await db
                    .doc('matches/$match')
                    .get(const GetOptions(source: Source.server)))
                .data();
        if (data?['isActive'] != true ||
            !(data?['users'] as List? ?? []).contains(widget.uid)) {
          if (mounted) _message('Esta conversación ya no está disponible.');
          return;
        }
        final sender = await profile(note.sender);
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChatScreen(matchId: match, uid: widget.uid, profile: sender),
            ),
          );
        }
      } else {
        _message('El contenido ya no está disponible.');
      }
    } catch (_) {
      if (mounted) _message('No se pudo abrir la notificación. Reintenta.');
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    widget.service.beforeLogout = null;
    unawaited(_arrivals?.cancel());
    unawaited(_opened?.cancel());
    unawaited(_foreground?.cancel());
    unawaited(_refresh?.cancel());
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _NotificationProvider(hub: this, child: widget.child);
}

class _NotificationProvider extends InheritedWidget {
  const _NotificationProvider({required this.hub, required super.child});
  final NotificationHubState hub;
  @override
  bool updateShouldNotify(_NotificationProvider oldWidget) =>
      oldWidget.hub != hub;
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context) {
    final hub = NotificationHub.of(context);
    if (hub == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: hub.totals,
      builder: (context, snapshot) {
        final unread = (snapshot.data?.data()?['unread'] as int?) ?? 0;
        return IconButton(
          tooltip: 'Notificaciones',
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationsScreen(hub: hub),
            ),
          ),
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.hub});
  final NotificationHubState hub;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Opening the inbox must get its own initial snapshot, even when the
  // background listener already received the latest page.
  late final _inboxStream = widget.hub.page.snapshots();
  final _anchors = <DocumentSnapshot<Map<String, dynamic>>>[];
  Future<QuerySnapshot<Map<String, dynamic>>>? _older;
  bool _saving = false;
  String? _settingsMessage;

  void _next(DocumentSnapshot<Map<String, dynamic>> doc) {
    setState(() {
      _anchors.add(doc);
      _loadOlder();
    });
  }

  void _loadOlder() {
    _older = _anchors.isEmpty
        ? null
        : widget.hub.page.startAfterDocument(_anchors.last).get();
  }

  Future<void> _toggle(bool enabled) async {
    setState(() {
      _saving = true;
      _settingsMessage = null;
    });
    try {
      final result = await widget.hub.changePush(enabled);
      if (mounted) setState(() => _settingsMessage = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _settingsMessage =
              'No se pudieron guardar las preferencias. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notificaciones')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const SectionHeading(
              'Tu actividad',
              icon: Icons.notifications_none_rounded,
              subtitle: 'Conexiones, mensajes y acreditación.',
            ),
            Card(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: widget.hub.settings,
                builder: (context, snapshot) => SwitchListTile(
                  title: const Text('Alertas push de la cuenta'),
                  subtitle: Text(
                    snapshot.hasError
                        ? 'No se pudieron consultar los ajustes.'
                        : _settingsMessage ??
                              (widget.hub.canPush
                                  ? 'Activa este dispositivo. Los avisos no muestran mensajes privados.'
                                  : 'El buzón funciona aquí. Push requiere un entorno FCM configurado.'),
                  ),
                  value: snapshot.data?.data()?['push'] == true,
                  onChanged:
                      widget.hub.canPush && !_saving && !snapshot.hasError
                      ? _toggle
                      : null,
                ),
              ),
            ),
            if (widget.hub.canPush)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _saving ? null : () => _toggle(true),
                  child: const Text('Activar en este dispositivo'),
                ),
              ),
            const SizedBox(height: 10),
            if (_older == null)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _inboxStream,
                builder: _rows,
              )
            else
              FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _older,
                builder: _rows,
              ),
          ],
        ),
      ),
    ),
  );
  Widget _rows(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const LinearProgressIndicator();
    }
    if (snapshot.hasError) {
      return const AppNotice(
        'No se pudieron cargar las notificaciones.',
        error: true,
      );
    }
    final docs = snapshot.data?.docs ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (docs.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.notifications_off_outlined),
              title: Text('Todavía no hay notificaciones.'),
            ),
          ),
        for (final doc in docs)
          _NoticeRow(
            key: ValueKey(doc.id),
            hub: widget.hub,
            notice: LigoNotice.fromDoc(doc),
          ),
        if (_anchors.isNotEmpty || docs.length == 25)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _anchors.isEmpty
                    ? null
                    : () => setState(() {
                        _anchors.removeLast();
                        _loadOlder();
                      }),
                child: const Text('Anterior'),
              ),
              OutlinedButton(
                onPressed: docs.length == 25 ? () => _next(docs.last) : null,
                child: const Text('Anteriores'),
              ),
            ],
          ),
      ],
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({super.key, required this.hub, required this.notice});
  final NotificationHubState hub;
  final LigoNotice notice;
  @override
  Widget build(BuildContext context) => FutureBuilder<DiscoveryCandidate?>(
    future: hub.profile(notice.sender),
    builder: (context, snapshot) {
      final sender = snapshot.data;
      final date = notice.date;
      final material = MaterialLocalizations.of(context);
      final timestamp = date == null
          ? 'Fecha no disponible'
          : '${material.formatShortDate(date.toLocal())} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date.toLocal()))}';
      return Card(
        color: notice.unread
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.30)
            : null,
        child: ListTile(
          leading: ClipOval(
            child: SizedBox.square(
              dimension: 42,
              child: sender == null || notice.isStoryReply
                  ? Icon(notice.icon)
                  : AppPhoto(url: sender.mainPhotoUrl),
            ),
          ),
          title: Text(
            notice.isStoryReply && sender != null
                ? '${sender.firstName} ${notice.description}'
                : sender == null
                ? notice.title
                : '${sender.firstName} · ${notice.title}',
            style: TextStyle(
              fontWeight: notice.unread ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: Text(
            notice.isStoryReply && sender != null
                ? timestamp
                : '${notice.description}\n$timestamp',
          ),
          trailing: notice.unread
              ? const Tooltip(
                  message: 'Sin leer',
                  child: Icon(Icons.circle, size: 9),
                )
              : null,
          onTap: () => hub.open(notice),
        ),
      );
    },
  );
}

class UnreadChatIcon extends StatelessWidget {
  const UnreadChatIcon(this.icon, {super.key});
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final hub = NotificationHub.of(context);
    if (hub == null) return Icon(icon);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: hub.totals,
      builder: (context, snapshot) {
        final count = snapshot.data?.data()?['messages'] as int? ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: Icon(icon),
        );
      },
    );
  }
}
