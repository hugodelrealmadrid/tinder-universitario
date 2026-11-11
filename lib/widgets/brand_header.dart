import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_ui.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const AppMark(size: 34),
      const SizedBox(width: 10),
      Expanded(
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class CampusLabel extends StatelessWidget {
  const CampusLabel({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.location_on_outlined, size: 16, color: AppColors.coral),
      SizedBox(width: 5),
      Flexible(
        child: Text(
          'Tu comunidad universitaria',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ),
    ],
  );
}
