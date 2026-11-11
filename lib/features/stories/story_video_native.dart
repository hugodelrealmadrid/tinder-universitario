import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

Future<({VideoPlayerController player, Future<void> Function() release})>
storyVideo(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp('ligo-story-');
  try {
    final file = await File('${directory.path}/story.mp4').writeAsBytes(bytes);
    return (
      player: VideoPlayerController.file(file),
      release: () async {
        await directory.delete(recursive: true);
      },
    );
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}
