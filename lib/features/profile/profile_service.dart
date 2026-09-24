import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart' show isAdult;
import 'photo_store.dart';
import 'student_profile.dart';
import '../discovery/discovery_publication.dart';

class ProfileService {
  ProfileService({FirebaseFirestore? firestore, PhotoStore? photos})
    : _db = firestore ?? FirebaseFirestore.instance,
      _photos = photos ?? FirebasePhotoStore();
  final FirebaseFirestore _db;
  final PhotoStore _photos;
  // Si Storage falla después de quitar una URL, la UI ofrece reintentar.
  final Set<String> pendingDeletes = {};
  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  Future<StudentProfile> load(String uid) async {
    final snapshot = await _user(
      uid,
    ).get(const GetOptions(source: Source.server));
    if (!snapshot.exists) {
      throw const ProfileException(
        'No se encontró tu perfil. Vuelve a iniciar sesión.',
      );
    }
    return StudentProfile.fromMap(snapshot.data()!);
  }

  Future<List<CatalogItem>> catalog(String collection) async {
    final snapshot = await _db
        .collection(collection)
        .where('isActive', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    final items = snapshot.docs
        .map((doc) => CatalogItem(doc.id, doc.data()['name'] as String))
        .toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  Future<bool> _activeCareer(String? id) async =>
      id != null &&
      (await _db
                  .collection('careers')
                  .doc(id)
                  .get(const GetOptions(source: Source.server)))
              .data()?['isActive'] ==
          true;

  Future<StudentProfile> save(
    String uid,
    StudentProfile draft, {
    required bool activate,
  }) async {
    if (!ProfileGender.isValid(draft.gender)) {
      throw const ProfileException('Selecciona Masculino o Femenino.');
    }
    if (draft.firstName.trim().length > 80 ||
        draft.lastName.trim().length > 80 ||
        draft.description.trim().length > maxDescriptionLength) {
      throw const ProfileException('Revisa la longitud de los campos.');
    }
    if (draft.birthDate != null && !isAdult(draft.birthDate!)) {
      throw const ProfileException('Debes tener al menos 18 años.');
    }
    if (draft.careerId != null && !await _activeCareer(draft.careerId)) {
      throw const ProfileException('Selecciona una carrera activa.');
    }
    if (draft.interestIds.length > maxInterests ||
        draft.interestIds.toSet().length != draft.interestIds.length) {
      throw const ProfileException('Selecciona hasta 5 intereses distintos.');
    }
    for (final id in draft.interestIds) {
      if ((await _db
                  .collection('interests')
                  .doc(id)
                  .get(const GetOptions(source: Source.server)))
              .data()?['isActive'] !=
          true) {
        throw const ProfileException(
          'Uno de los intereses ya no está activo. Recarga el catálogo.',
        );
      }
    }
    await _db.runTransaction((tx) async {
      final ref = _user(uid);
      final data = (await tx.get(ref)).data()!;
      final current = StudentProfile.fromMap(data);
      // Nunca reemplazar fotos con las de una copia antigua del formulario.
      final merged = draft.withPhotos(current.photoUrls, current.mainPhotoUrl);
      final changes = <String, dynamic>{
        ...draft.editableFields(),
        'isActive': activate && merged.isComplete,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.update(ref, changes);
      DiscoveryPublication.write(tx, _db, uid, {...data, ...changes});
    });
    return load(uid);
  }

  Future<void> _changePhotos(
    String uid,
    ({List<String> urls, String? main}) Function(StudentProfile) change,
  ) async {
    await _db.runTransaction((tx) async {
      final ref = _user(uid);
      final data = (await tx.get(ref)).data()!;
      final current = StudentProfile.fromMap(data);
      final changed = change(current);
      final next = current.withPhotos(changed.urls, changed.main);
      final career = current.careerId == null
          ? null
          : await tx.get(_db.collection('careers').doc(current.careerId));
      final changes = <String, dynamic>{
        'photoUrls': changed.urls,
        'mainPhotoUrl': changed.main,
        'isActive':
            current.isActive &&
            next.isComplete &&
            career?.data()?['isActive'] == true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.update(ref, changes);
      DiscoveryPublication.write(tx, _db, uid, {...data, ...changes});
    });
  }

  Future<void> upload(String uid, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
      throw const ProfileException('Cada imagen debe pesar como máximo 5 MB.');
    }
    final type = imageContentType(bytes);
    if ((await load(uid)).photoUrls.length >= maxPhotos) {
      throw const ProfileException('Puedes guardar hasta 6 fotografías.');
    }
    final fileId = _db.collection('users').doc().id;
    final url = await _photos.upload(uid, fileId, bytes, type);
    try {
      await _changePhotos(uid, (current) {
        if (current.photoUrls.contains(url)) {
          return (urls: current.photoUrls, main: current.mainPhotoUrl);
        }
        if (current.photoUrls.length >= maxPhotos) {
          throw const ProfileException('Puedes guardar hasta 6 fotografías.');
        }
        return (
          urls: [...current.photoUrls, url],
          main: current.mainPhotoUrl ?? url,
        );
      });
    } catch (_) {
      // Una respuesta perdida no significa que la transacción no se guardó.
      // Solo eliminamos el archivo si una lectura del servidor confirma que
      // no está referenciado. Si no hay red, se conserva para no romper datos.
      final current = await load(uid);
      if (current.photoUrls.contains(url)) return;
      pendingDeletes.add(url);
      try {
        await retryDelete(uid, url);
      } catch (_) {
        /* La UI ofrece reintento. */
      }
      rethrow;
    }
  }

  Future<void> chooseMain(String uid, String url) =>
      _changePhotos(uid, (current) {
        if (!current.photoUrls.contains(url)) {
          throw const ProfileException(
            'La fotografía ya no está disponible. Recarga el perfil.',
          );
        }
        return (urls: current.photoUrls, main: url);
      });

  Future<void> remove(String uid, String url) async {
    // Primero quitar la referencia evita dejar una foto rota si Firestore falla.
    await _changePhotos(uid, (current) {
      final urls = current.photoUrls.where((photo) => photo != url).toList();
      return (
        urls: urls,
        main: urls.contains(current.mainPhotoUrl)
            ? current.mainPhotoUrl
            : urls.firstOrNull,
      );
    });
    pendingDeletes.add(url);
    await retryDelete(uid, url);
  }

  Future<void> retryDelete(String uid, String url) async {
    await _photos.delete(uid, url);
    pendingDeletes.remove(url);
  }
}
