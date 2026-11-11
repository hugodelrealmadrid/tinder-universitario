import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../verification/backend_client.dart';
import 'private_photo_path.dart';
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
  FirebasePhotoStore({FirebaseStorage? storage, this.auth});
  final FirebaseAuth? auth;
  @override
  Future<String> upload(
    String uid,
    String fileId,
    Uint8List bytes,
    String contentType,
  ) async {
    final path = 'profile_photos/$uid/$fileId';
    final client = VerificationClient(auth: auth);
    try {
      await client.uploadPhoto(path, bytes, contentType);
      return path;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> delete(String uid, String url) async {
    if (!isPrivatePhotoPath(url) || url.split('/')[1] != uid) {
      throw const ProfileException('La fotografía no pertenece a tu carpeta.');
    }
    final client = VerificationClient(auth: auth);
    try {
      await client.deletePhoto(url);
    } finally {
      client.close();
    }
  }
}
