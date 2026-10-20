import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_ui.dart';
import '../discovery/discovery_models.dart';
import 'student_match.dart';

class MatchProfileScreen extends StatelessWidget {
  const MatchProfileScreen({
    super.key,
    required this.viewer,
    required this.target,
    this.firestore,
  });
  final String viewer, target;
  final FirebaseFirestore? firestore;
  @override
  Widget build(BuildContext context) {
    final db = firestore ?? FirebaseFirestore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil del match')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db
            .doc('matches/${StudentMatch.idFor(viewer, target)}')
            .snapshots(),
        builder: (context, pair) {
          if (pair.hasError ||
              (pair.hasData && pair.data!.data()?['isActive'] != true)) {
            return const Center(
              child: Text('Este perfil ya no está disponible.'),
            );
          }
          if (!pair.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _PublicProfile(db: db, target: target);
        },
      ),
    );
  }
}

class _PublicProfile extends StatefulWidget {
  const _PublicProfile({required this.db, required this.target});
  final FirebaseFirestore db;
  final String target;
  @override
  State<_PublicProfile> createState() => _PublicProfileState();
}

class _PublicProfileState extends State<_PublicProfile> {
  late final Future<
    (DiscoveryCandidate, Map<String, String>, Map<String, String>)
  >
  _profile = _load();
  Future<(DiscoveryCandidate, Map<String, String>, Map<String, String>)>
  _load() async {
    Map<String, dynamic>? data;
    try {
      data =
          (await widget.db
                  .doc('matchProfiles/${widget.target}')
                  .get(const GetOptions(source: Source.server)))
              .data();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    // Compatibilidad: hasta que el dueño guarde, su ficha anterior ofrece una foto.
    data ??=
        (await widget.db
                .doc('discoveryCards/${widget.target}')
                .get(const GetOptions(source: Source.server)))
            .data();
    if (data == null) throw StateError('Perfil no disponible');
    Future<Map<String, String>> catalog(String name) async => {
      for (final d
          in (await widget.db
                  .collection(name)
                  .get(const GetOptions(source: Source.server)))
              .docs)
        d.id: d.data()['name'] as String,
    };
    return (
      DiscoveryCandidate.fromMap(widget.target, data),
      await catalog('careers'),
      await catalog('interests'),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text(
            'No se pudo cargar el perfil. Vuelve a abrirlo para reintentar.',
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final (p, careers, interests) = snapshot.data!;
      final photos = [
        p.mainPhotoUrl,
        ...p.photoUrls.where((u) => u != p.mainPhotoUrl),
      ];
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                height: 360,
                child: PageView(
                  children: photos.map((u) => AppPhoto(url: u)).toList(),
                ),
              ),
              Text('${photos.length} fotos · Desliza para verlas'),
              Text(
                '${p.firstName}, ${p.age}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(careers[p.careerId] ?? 'Carrera no disponible'),
              const SizedBox(height: 16),
              Text(p.description),
              Wrap(
                spacing: 8,
                children: p.interestIds
                    .where(interests.containsKey)
                    .map((id) => Chip(label: Text(interests[id]!)))
                    .toList(),
              ),
            ],
          ),
        ),
      );
    },
  );
}
