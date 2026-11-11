import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/motion_entrance.dart';

Future<bool> showMatchCelebration(
  BuildContext context, {
  required String name,
  required String? ownPhoto,
  required String? otherPhoto,
  Widget Function(String path)? photoBuilder,
}) async {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        transitionDuration: reduce ? Duration.zero : AppMotion.normal,
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, _, _) {
          Widget avatar(String? photo) => ClipOval(
            child: SizedBox.square(
              dimension: 82,
              child: photo != null && photoBuilder != null
                  ? photoBuilder(photo)
                  : AppPhoto(url: photo),
            ),
          );
          final colors = Theme.of(context).colorScheme;
          return AlertDialog(
            scrollable: true,
            title: const Text('¡Es un match!', textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MotionEntrance(
                  distance: 12,
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: avatar(ownPhoto)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.favorite_rounded,
                            color: colors.primary,
                            size: 32,
                          ),
                        ),
                        Flexible(child: avatar(otherPhoto)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Tú y $name se dieron like.', textAlign: TextAlign.center),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => Navigator.pop(context, true),
                label: const Text('Abrir conversación'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Continuar descubriendo'),
              ),
            ],
          );
        },
      ) ??
      false;
}
