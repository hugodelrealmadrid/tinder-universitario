import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../widgets/app_ui.dart';
import '../verification/backend_client.dart';
import 'story_video.dart';

typedef _Row = Map<String, dynamic>;
List<_Row> _rows(Object? rows) => (rows as List).cast<_Row>();

class StoryShelf extends StatefulWidget {
  const StoryShelf({super.key, this.client});
  final VerificationClient? client;
  @override
  State<StoryShelf> createState() => _StoryShelfState();
}

class _StoryShelfState extends State<StoryShelf> {
  late final _client = widget.client ?? VerificationClient();
  final _elapsed = Stopwatch();
  List<_Row> _groups = [];
  int _serverNow = 0;
  String? _cursor;
  bool _busy = false;
  bool _error = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  int get _now => _serverNow + _elapsed.elapsedMilliseconds;
  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final page = await _client.stories('feed', cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        _serverNow = page['serverNow'] as int;
        _elapsed
          ..reset()
          ..start();
        _groups = [...(more ? _groups : <_Row>[]), ..._rows(page['groups'])];
        _cursor = page['nextCursor'] as String?;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _StoryComposer(client: _client)),
    );
    if (mounted && saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <_Row>[];
    for (final group in _groups) {
      final active = _rows(group['stories'])
          .where(
            (s) =>
                (s['expiresAt'] as int) > _now &&
                (kIsWeb || s['mime'] != 'video/mp4'),
          )
          .toList();
      if (active.isNotEmpty) groups.add({...group, 'stories': active});
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Historias', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _bubble(
                  'Publicar',
                  null,
                  false,
                  _publish,
                  icon: Icons.add_rounded,
                ),
                for (var i = 0; i < groups.length; i++)
                  _bubble(
                    groups[i]['own'] == true
                        ? 'Tu historia'
                        : groups[i]['name'] as String,
                    groups[i]['photo'] as String?,
                    _rows(groups[i]['stories']).any((s) => s['seen'] == false),
                    () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => _StoryViewer(
                            client: _client,
                            groups: groups,
                            start: i,
                            now: () => _now,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
                  ),
                if (_cursor != null)
                  _bubble(
                    'Más',
                    null,
                    false,
                    () => _load(more: true),
                    icon: Icons.more_horiz,
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error)
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar historias'),
            ),
          if (!_busy && !_error && groups.isEmpty)
            const Text('Las historias de tus matches aparecerán aquí.'),
        ],
      ),
    );
  }

  Widget _bubble(
    String label,
    String? photo,
    bool unseen,
    VoidCallback action, {
    IconData? icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 84,
      child: Semantics(
        button: true,
        label: unseen ? '$label, historia nueva' : label,
        onTap: action,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: action,
          child: ExcludeSemantics(
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: unseen
                          ? [colors.primary, colors.tertiary]
                          : [colors.outlineVariant, colors.outlineVariant],
                    ),
                  ),
                  child: ClipOval(
                    child: icon == null && photo != null
                        ? AppPhoto(url: photo)
                        : ColoredBox(
                            color: colors.surface,
                            child: Icon(icon ?? Icons.person_outline),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Video = ({
  VideoPlayerController player,
  Future<void> Function() release,
});
Future<_Video> _openVideo(Uint8List bytes) async {
  final video = await storyVideo(bytes);
  try {
    await video.player.initialize();
    return video;
  } catch (_) {
    await _releaseVideo(video);
    rethrow;
  }
}

Future<void> _releaseVideo(_Video? video) async {
  if (video == null) return;
  try {
    await video.player.dispose();
  } finally {
    await video.release();
  }
}

Widget _media(Uint8List bytes, _Video? video) => video == null
    ? Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('No se pudo mostrar la foto.')),
      )
    : Center(
        child: AspectRatio(
          aspectRatio: video.player.value.aspectRatio,
          child: VideoPlayer(video.player),
        ),
      );

class _StoryComposer extends StatefulWidget {
  const _StoryComposer({required this.client});
  final VerificationClient client;
  @override
  State<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<_StoryComposer> {
  final _caption = TextEditingController();
  Uint8List? _bytes;
  _Video? _video;
  String? _mime;
  String? _error;
  bool _picking = false;
  double? _progress;

  @override
  void dispose() {
    _caption.dispose();
    unawaited(_releaseVideo(_video));
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          if (kIsWeb) 'mp4',
        ],
        withData: false,
        withReadStream: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      final mime = switch (file.extension?.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'mp4' when kIsWeb => 'video/mp4',
        _ => throw const FormatException(
          kIsWeb
              ? 'Elige una foto JPG, PNG o WebP, o un video MP4.'
              : 'Elige una foto JPG, PNG o WebP.',
        ),
      };
      final limit = (mime == 'video/mp4' ? 15 : 5) * 1024 * 1024;
      if (file.size <= 0 || file.size > limit) {
        throw const FormatException(
          kIsWeb
              ? 'Las fotos admiten hasta 5 MB y los videos hasta 15 MB.'
              : 'Las fotos admiten hasta 5 MB.',
        );
      }
      final data = BytesBuilder(copy: false);
      await for (final chunk in file.readStream!) {
        if (data.length + chunk.length > limit) {
          throw const FormatException('El archivo supera el límite permitido.');
        }
        data.add(chunk);
      }
      final bytes = data.takeBytes();
      _Video? video;
      if (mime == 'video/mp4') {
        video = await _openVideo(bytes);
        final duration = video.player.value.duration;
        if (duration <= Duration.zero ||
            duration > const Duration(seconds: 30)) {
          await _releaseVideo(video);
          throw const FormatException(
            'El video debe durar como máximo 30 segundos.',
          );
        }
      } else {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
        codec.dispose();
      }
      if (!mounted) {
        await _releaseVideo(video);
        return;
      }
      final old = _video;
      setState(() {
        _video = video;
        _bytes = bytes;
        _mime = mime;
      });
      await _releaseVideo(old);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'No se pudo abrir el archivo. Prueba con otro.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _publish() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await _video?.player.pause();
      await widget.client.publishStory(_bytes!, _mime!, _caption.text, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error =
              'No se pudo publicar. Comprueba el formato o intenta nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _progress == null,
    child: Scaffold(
      appBar: AppBar(title: const Text('Nueva historia')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Tu historia dura 24 horas y solo pueden verla tus matches activos.',
                ),
                const SizedBox(height: 12),
                if (_bytes case final bytes?)
                  SizedBox(height: 280, child: _media(bytes, _video)),
                if (_video case final video?)
                  TextButton.icon(
                    onPressed: _progress != null
                        ? null
                        : () => video.player.value.isPlaying
                              ? video.player.pause()
                              : video.player.play(),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Reproducir o pausar vista previa'),
                  ),
                OutlinedButton.icon(
                  onPressed: _picking || _progress != null ? null : _pick,
                  icon: const Icon(Icons.perm_media_outlined),
                  label: const Text(
                    kIsWeb ? 'Elegir foto o video' : 'Elegir fotografía',
                  ),
                ),
                const Text(
                  kIsWeb
                      ? 'JPG, PNG o WebP hasta 5 MB. MP4 hasta 15 MB y 30 segundos.'
                      : 'JPG, PNG o WebP hasta 5 MB.',
                ),
                TextField(
                  controller: _caption,
                  enabled: _progress == null,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Texto opcional',
                  ),
                ),
                if (_error case final error?)
                  Semantics(liveRegion: true, child: Text(error)),
                if (_picking) const LinearProgressIndicator(),
                if (_progress case final progress?) ...[
                  LinearProgressIndicator(
                    value: progress < 1 ? progress : null,
                  ),
                  Text(progress < 1 ? 'Subiendo…' : 'Validando y publicando…'),
                ],
                FilledButton(
                  onPressed: _bytes == null || _picking || _progress != null
                      ? null
                      : _publish,
                  child: const Text('Publicar historia'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _StoryViewer extends StatefulWidget {
  const _StoryViewer({
    required this.client,
    required this.groups,
    required this.start,
    required this.now,
  });
  final VerificationClient client;
  final List<_Row> groups;
  final int start;
  final int Function() now;
  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer>
    with WidgetsBindingObserver {
  late final _entries = [
    for (final group in widget.groups)
      for (final story in _rows(group['stories'])) (group: group, story: story),
  ];
  late int _index = widget.groups
      .take(widget.start)
      .fold(0, (sum, g) => sum + _rows(g['stories']).length);
  final _watch = Stopwatch();
  Timer? _tick;
  Uint8List? _bytes;
  _Video? _video;
  bool _error = false;
  bool _paused = false;
  bool _muted = true;
  bool _foreground = true;
  int _revision = 0;
  double _progress = 0;
  String get _id => _entries[_index].story['id'] as String;
  bool get _own => _entries[_index].group['own'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _tick = Timer.periodic(const Duration(milliseconds: 50), (_) => _update());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revision++;
    _tick?.cancel();
    unawaited(_releaseVideo(_video));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _playback();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    final id = _id;
    final old = _video;
    setState(() {
      _bytes = null;
      _video = null;
      _error = false;
      _progress = 0;
      _watch
        ..stop()
        ..reset();
    });
    try {
      await _releaseVideo(old);
      final bytes = await widget.client.storyMedia(id);
      if (!mounted || revision != _revision) return;
      final video = _entries[_index].story['mime'] == 'video/mp4'
          ? await _openVideo(bytes)
          : null;
      if (!mounted || revision != _revision) {
        await _releaseVideo(video);
        return;
      }
      setState(() {
        _bytes = bytes;
        _video = video;
      });
      await video?.player.setVolume(_muted ? 0 : 1);
      if (!mounted || revision != _revision) return;
      _playback();
      if (!_own) {
        unawaited(
          widget.client.storyAction('view', id).catchError((Object _) {}),
        );
      }
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _error = true);
    }
  }

  void _playback() {
    if (_bytes == null || _error) return;
    final play = !_paused && _foreground;
    if (play) {
      _watch.start();
    } else {
      _watch.stop();
    }
    final player = _video?.player;
    if (player != null) {
      unawaited(
        (play ? player.play() : player.pause()).catchError((Object _) {
          if (mounted && _video?.player == player) {
            setState(() => _error = true);
          }
        }),
      );
    }
  }

  void _update() {
    if (_error || !_foreground) return;
    if ((_entries[_index].story['expiresAt'] as int) <= widget.now()) {
      _watch.stop();
      final video = _video;
      ++_revision;
      setState(() {
        _error = true;
        _bytes = null;
        _video = null;
      });
      unawaited(_releaseVideo(video));
      return;
    }
    if (_bytes == null || _paused) return;
    final value = _video?.player.value;
    if (value?.hasError == true) {
      setState(() => _error = true);
      return;
    }
    final p = value == null
        ? _watch.elapsedMilliseconds / 6000
        : value.position.inMilliseconds / value.duration.inMilliseconds;
    if (p >= 1 || value?.isCompleted == true) {
      _move(1);
    } else {
      setState(() => _progress = p.clamp(0.0, 1.0));
    }
  }

  void _move(int offset) {
    final next = _index + offset;
    if (next >= _entries.length) {
      _watch.stop();
      _tick?.cancel();
      Navigator.pop(context);
    } else {
      _index = next < 0 ? 0 : next;
      _load();
    }
  }

  void _hold(bool value) {
    _paused = value;
    _playback();
  }

  Future<void> _action(String action) async {
    final id = _id;
    _hold(true);
    try {
      if (action == 'viewers') {
        await showModalBottomSheet<void>(
          context: context,
          builder: (_) => _StoryViews(client: widget.client, id: id),
        );
        return;
      }
      final reply = action == 'reply';
      final result = await showDialog<String>(
        context: context,
        builder: (_) => _StoryActionDialog(action: action),
      );
      if (result == null || !mounted) return;
      await widget.client.storyAction(action, id, text: reply ? result : null);
      if (!mounted) return;
      if (action == 'delete') {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reply ? 'Respuesta enviada al chat.' : 'Reporte enviado.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La acción no está disponible.')),
        );
      }
    } finally {
      if (mounted) _hold(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entries[_index];
    final caption = entry.story['caption'] as String;
    final groupItems = _rows(entry.group['stories']);
    final active = groupItems.indexOf(entry.story);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < groupItems.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: LinearProgressIndicator(
                              value: i == active
                                  ? _progress
                                  : (i < active ? 1 : 0),
                              backgroundColor: Colors.white30,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  title: Text(
                    entry.group['own'] == true
                        ? 'Tu historia'
                        : entry.group['name'] as String,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: IconButton(
                    tooltip: 'Cerrar historia',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (_) => _hold(true),
                    onLongPressEnd: (_) => _hold(false),
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) > 300) {
                        Navigator.pop(context);
                      }
                    },
                    onTapUp: (d) {
                      final width = context.size?.width ?? 0;
                      _move(
                        d.localPosition.dx < (width.clamp(0, 580) / 2) ? -1 : 1,
                      );
                    },
                    child: SizedBox.expand(
                      child: _error
                          ? const Center(
                              child: Text(
                                'Esta historia ya no está disponible.',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : _bytes == null
                          ? const Center(child: CircularProgressIndicator())
                          : _media(_bytes!, _video),
                    ),
                  ),
                ),
                if (caption.isNotEmpty && _bytes != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      caption,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Historia anterior',
                      onPressed: () => _move(-1),
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Historia siguiente',
                      onPressed: () => _move(1),
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                    ),
                    if (_video case final video?)
                      IconButton(
                        tooltip: _muted ? 'Activar sonido' : 'Silenciar',
                        onPressed: () {
                          setState(() => _muted = !_muted);
                          video.player.setVolume(_muted ? 0 : 1);
                        },
                        icon: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                        ),
                      ),
                    if (!_error && _bytes != null) ...[
                      TextButton(
                        onPressed: () => _action(_own ? 'viewers' : 'reply'),
                        child: Text(_own ? 'Visualizaciones' : 'Responder'),
                      ),
                      IconButton(
                        tooltip: _own
                            ? 'Eliminar historia'
                            : 'Reportar historia',
                        onPressed: () => _action(_own ? 'delete' : 'report'),
                        icon: Icon(
                          _own ? Icons.delete_outline : Icons.flag_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryActionDialog extends StatefulWidget {
  const _StoryActionDialog({required this.action});
  final String action;
  @override
  State<_StoryActionDialog> createState() => _StoryActionDialogState();
}

class _StoryActionDialogState extends State<_StoryActionDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.action == 'reply';
    final remove = widget.action == 'delete';
    return AlertDialog(
      title: Text(
        reply
            ? 'Responder por chat'
            : remove
            ? 'Eliminar historia'
            : 'Reportar historia',
      ),
      content: reply
          ? TextField(
              controller: _text,
              autofocus: true,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Tu mensaje'),
            )
          : Text(
              remove
                  ? 'La historia dejará de estar disponible.'
                  : 'El equipo de moderación recibirá tu reporte.',
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: reply && _text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _text.text.trim()),
          child: Text(reply ? 'Enviar' : 'Confirmar'),
        ),
      ],
    );
  }
}

class _StoryViews extends StatefulWidget {
  const _StoryViews({required this.client, required this.id});
  final VerificationClient client;
  final String id;
  @override
  State<_StoryViews> createState() => _StoryViewsState();
}

class _StoryViewsState extends State<_StoryViews> {
  final _items = <_Row>[];
  String? _cursor;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final page = await widget.client.stories(
        'viewers',
        id: widget.id,
        cursor: _cursor,
      );
      if (mounted) {
        setState(() {
          _items.addAll(_rows(page['items']));
          _cursor = page['nextCursor'] as String?;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Visualizaciones', style: Theme.of(context).textTheme.titleLarge),
        for (final item in _items)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(item['name'] as String),
            subtitle: item['at'] is int
                ? Text(
                    MaterialLocalizations.of(context).formatShortDate(
                      DateTime.fromMillisecondsSinceEpoch(item['at'] as int),
                    ),
                  )
                : null,
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_error)
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        if (!_loading && !_error && _items.isEmpty)
          const Text('Todavía nadie vio esta historia.'),
        if (!_loading && !_error && _cursor != null)
          TextButton(onPressed: _load, child: const Text('Ver más')),
      ],
    ),
  );
}
