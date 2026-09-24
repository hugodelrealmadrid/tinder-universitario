import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'student_profile.dart';

abstract class PhotoStore {
  Future<String> upload(
    String uid,
    String fileId,
    Uint8List bytes,
    String contentType,
  );
  Future<void> delete(String uid, String url);
}

class FirebasePhotoStore implements PhotoStore {
  FirebasePhotoStore({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;
  final FirebaseStorage _storage;
  @override
  Future<String> upload(
    String uid,
    String fileId,
    Uint8List bytes,
    String contentType,
  ) async {
    final ref = _storage.ref('profile_photos/$uid/$fileId');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  @override
  Future<void> delete(String uid, String url) async {
    final ref = _storage.refFromURL(url);
    if (ref.bucket != _storage.ref().bucket ||
        ref.parent?.fullPath != 'profile_photos/$uid') {
      throw const ProfileException('La fotografía no pertenece a tu carpeta.');
    }
    try {
      await ref.delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }
}
