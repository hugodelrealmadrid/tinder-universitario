import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart' show isAdult;
import '../auth/academic_selector.dart';
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

  Future<Set<String>> campusCareers(String university, String campus) async {
    final options = await AcademicDirectory(
      _db,
    ).options('universities/$university/campuses/$campus/offerings');
    return options.map((item) => item.id).toSet();
  }

  Future<void> completeAffiliation(String uid, AcademicChoice choice) async {
    await _db.runTransaction((tx) async {
      final ref = _user(uid);
      final data = (await tx.get(ref)).data();
      if (data == null ||
          data['campusId'] != null ||
          (data['universityId'] != null &&
              data['universityId'] != choice.universityId) ||
          (data['careerId'] != null && data['careerId'] != choice.careerId)) {
        throw const ProfileException(
          'La afiliación guardada cambió. Recarga el perfil.',
        );
      }
      final changes = <String, dynamic>{
        'universityId': choice.universityId,
        'campusId': choice.campusId,
        'careerId': choice.careerId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.update(ref, changes);
      DiscoveryPublication.write(tx, _db, uid, {...data, ...changes});
    });
  }

  Future<List<CatalogItem>> catalog(
    String collection, {
    List<String> retainedIds = const [],
  }) async {
    if (!['careers', 'interests'].contains(collection)) {
      throw const ProfileException('Catálogo no válido.');
    }
    final snapshot = await _db
        .collection(collection)
        .where('isActive', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    final items = snapshot.docs
        .map((d) => CatalogItem.fromMap(d.id, d.data()))
        .toList();
    for (final id in retainedIds.toSet()) {
      if (items.any((x) => x.id == id)) continue;
      final d = await _db
          .collection(collection)
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (d.exists) {
        final item = CatalogItem.fromMap(d.id, d.data()!);
        items.add(item);
      }
    }
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

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
    if (draft.interestIds.length > maxInterests ||
        draft.interestIds.toSet().length != draft.interestIds.length) {
      throw const ProfileException('Selecciona hasta 5 intereses distintos.');
    }
    await _db.runTransaction((tx) async {
      final ref = _user(uid);
      final data = (await tx.get(ref)).data()!;
      final current = StudentProfile.fromMap(data);
      if (draft.careerId != current.careerId && draft.careerId != null) {
        final c = (await tx.get(_db.doc('careers/${draft.careerId!}'))).data();
        if (c?['isActive'] != true) {
          throw const ProfileException('Selecciona una carrera activa.');
        }
      }
      for (final id in draft.interestIds.where(
        (id) => !current.interestIds.contains(id),
      )) {
        if ((await tx.get(_db.doc('interests/$id'))).data()?['isActive'] !=
            true) {
          throw const ProfileException(
            'Selecciona intereses activos del catálogo.',
          );
        }
      }

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
            current.isActive && next.isComplete && career?.exists == true,
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
