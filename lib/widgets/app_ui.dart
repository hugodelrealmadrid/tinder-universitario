import '../features/profile/private_profile_photo.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Símbolo vectorial LIGO. Misma geometría que los SVG entregables.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'LIGO · llama',
    image: true,
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: LigoFlamePainter(color: color)),
    ),
  );
}

class LigoFlamePainter extends CustomPainter {
  const LigoFlamePainter({this.color});
  final Color? color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 108, size.height / 108);
    final path = Path()
      ..moveTo(52, 4)
      ..cubicTo(65, 22, 71, 29, 62, 48)
      ..cubicTo(77, 46, 81, 31, 78, 24)
      ..cubicTo(98, 45, 100, 62, 93, 78)
      ..cubicTo(86, 95, 65, 102, 46, 97)
      ..cubicTo(17, 91, 10, 72, 16, 54)
      ..cubicTo(20, 43, 30, 34, 38, 27)
      ..cubicTo(35, 43, 39, 49, 45, 48)
      ..cubicTo(56, 43, 58, 22, 52, 4)
      ..close();
    final paint = Paint()..isAntiAlias = true;
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = AppColors.gradient.createShader(
        const Rect.fromLTWH(0, 0, 108, 108),
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LigoFlamePainter old) => old.color != color;
}

class LigoLogo extends StatelessWidget {
  const LigoLogo({
    super.key,
    this.size = 36,
    this.dark = false,
    this.vertical = false,
  });
  final double size;
  final bool dark, vertical;
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      AppMark(size: size),
      SizedBox(width: vertical ? 0 : 6, height: vertical ? 8 : 0),
      SizedBox(
        width: size * 2.5,
        height: size * .82,
        child: CustomPaint(
          painter: LigoWordmarkPainter(
            dark || Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : AppColors.ink,
          ),
        ),
      ),
    ];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class LigoWordmarkPainter extends CustomPainter {
  const LigoWordmarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 202, s.height / 68);
    c.translate(6, 5);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 12
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(6, 4)
      ..lineTo(6, 54)
      ..lineTo(39, 54)
      ..moveTo(60, 4)
      ..lineTo(60, 54)
      ..moveTo(127, 13)
      ..cubicTo(119, 0, 91, 0, 83, 18)
      ..cubicTo(71, 45, 94, 65, 122, 50)
      ..lineTo(122, 31)
      ..lineTo(103, 31);
    c.drawPath(path, paint);
    c.drawOval(const Rect.fromLTWH(143, 2, 46, 54), paint);
  }

  @override
  bool shouldRepaint(covariant LigoWordmarkPainter old) => old.color != color;
}

/// Nunca incorpora la URL, el token ni el texto de la excepción al diagnóstico.
String photoFailureCode(Object error) {
  if (error is NetworkImageLoadException) {
    return switch (error.statusCode) {
      401 || 403 => 'access-denied',
      404 => 'not-found',
      _ => 'network',
    };
  }
  return 'load-failed';
}

class AppPhoto extends StatefulWidget {
  const AppPhoto({
    super.key,
    required this.url,
    this.label = 'Fotografía de perfil',
    this.alignment = Alignment.topCenter,
  });
  final String? url;
  final String label;
  final Alignment alignment;
  @override
  State<AppPhoto> createState() => _AppPhotoState();
}

class _AppPhotoState extends State<AppPhoto> {
  bool _reported = false;
  int _attempt = 0;
  @override
  void didUpdateWidget(covariant AppPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _reported = false;
  }

  Future<void> _retry() async {
    setState(() {
      _attempt++;
      _reported = false;
    });
  }

  Widget _failed(Object error) {
    if (!_reported) {
      _reported = true;
      debugPrint('AppPhoto: ${photoFailureCode(error)}');
    }
    return Tooltip(
      message: 'No se pudo cargar la fotografía. Pulsa para reintentar.',
      child: Semantics(
        label: 'Fotografía no disponible. Reintentar',
        button: true,
        child: InkWell(onTap: _retry, child: _placeholder(failed: true)),
      ),
    );
  }

  Widget _placeholder({bool failed = false}) => ColoredBox(
    color: AppColors.rose,
    child: Center(
      child: Icon(
        failed
            ? Icons.image_not_supported_outlined
            : Icons.person_outline_rounded,
        size: 40,
        color: AppColors.coral,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    image: true,
    child: widget.url == null || widget.url!.isEmpty
        ? _placeholder()
        : PrivateProfilePhoto(
            key: ValueKey('${widget.url}:$_attempt'),
            path: widget.url!,
            alignment: widget.alignment,
            placeholder: _placeholder(),
            failure: (error, retry) => _failed(error),
          ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    required this.icon,
    this.subtitle,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.rose,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.coral, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AppNotice extends StatelessWidget {
  const AppNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFEBEE) : const Color(0xFFECF3FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            color: error ? AppColors.danger : AppColors.blue,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: error ? AppColors.danger : AppColors.ink),
            ),
          ),
        ],
      ),
    ),
  );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.rose,
            ),
            child: Icon(icon, color: AppColors.coral, size: 42),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
