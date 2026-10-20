import '../features/profile/private_profile_photo.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Marca propia, construida con iconografía Material; no utiliza assets de Tinder.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(Icons.school_rounded, color: Colors.white, size: size * .55),
    ),
  );
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
  });
  final String? url;
  final String label;
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
                Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
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
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
