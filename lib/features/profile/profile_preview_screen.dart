import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../preferences/discovery_preferences.dart' show ageOn;
import 'student_profile.dart';

class ProfilePreviewScreen extends StatelessWidget {
  const ProfilePreviewScreen({
    super.key,
    required this.profile,
    required this.careers,
    required this.interests,
  });
  final StudentProfile profile;
  final List<CatalogItem> careers, interests;
  @override
  Widget build(BuildContext context) {
    final photos = [
      if (profile.mainPhotoUrl != null) profile.mainPhotoUrl!,
      ...profile.photoUrls.where((url) => url != profile.mainPhotoUrl),
    ];
    final career = careers.where((c) => c.id == profile.careerId);
    return Scaffold(
      appBar: AppBar(title: const Text('Vista previa')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const AppNotice(
                'Vista previa de tus datos actuales. Guarda los cambios para publicarlos.',
              ),
              SizedBox(
                height: 360,
                child: photos.isEmpty
                    ? const AppPhoto(url: null)
                    : PageView(
                        children: photos
                            .map((url) => AppPhoto(url: url))
                            .toList(),
                      ),
              ),
              if (photos.length > 1)
                Text('${photos.length} fotos · Desliza para verlas'),
              const SizedBox(height: 16),
              Text(
                '${profile.firstName.trim().isEmpty ? "Tu nombre" : profile.firstName.trim()}${profile.birthDate == null ? "" : ", ${ageOn(profile.birthDate!, today: DateTime.now())}"}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (career.isNotEmpty) Text(career.first.name),
              const SizedBox(height: 16),
              Text(
                profile.description.trim().isEmpty
                    ? 'Sin descripción todavía.'
                    : profile.description,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: interests
                    .where((i) => profile.interestIds.contains(i.id))
                    .map((i) => Chip(label: Text(i.name)))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
