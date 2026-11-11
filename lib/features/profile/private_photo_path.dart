/// Referencia opaca a un objeto privado; nunca una URL ni un token de descarga.
bool isPrivatePhotoPath(String value) => RegExp(
  r'^profile_photos/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9_-]{1,128}$',
).hasMatch(value);
