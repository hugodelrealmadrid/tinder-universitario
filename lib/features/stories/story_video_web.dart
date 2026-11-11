import 'dart:js_interop';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

Future<({VideoPlayerController player, Future<void> Function() release})>
storyVideo(Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'video/mp4'),
  );
  final url = web.URL.createObjectURL(blob);
  return (
    player: VideoPlayerController.networkUrl(Uri.parse(url)),
    release: () async {
      web.URL.revokeObjectURL(url);
    },
  );
}
