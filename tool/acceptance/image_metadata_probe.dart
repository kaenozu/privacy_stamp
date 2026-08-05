import 'dart:convert';
import 'dart:io';

import 'image_metadata.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/acceptance/image_metadata_probe.dart <image>');
    exitCode = 64;
    return;
  }

  try {
    final metadata = await inspectAcceptanceImage(arguments.single);
    stdout.writeln(jsonEncode(metadata.toJson()));
  } on Object catch (error) {
    stderr.writeln('Image metadata probe failed: $error');
    exitCode = 1;
  }
}
