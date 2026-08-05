import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

final class AcceptanceImageMetadata {
  const AcceptanceImageMetadata({
    required this.format,
    required this.width,
    required this.height,
    required this.gpsPresent,
    required this.metadataContainerPresent,
  });

  final String format;
  final int width;
  final int height;
  final bool gpsPresent;
  final bool metadataContainerPresent;

  int get pixels => width * height;

  Map<String, Object> toJson() => <String, Object>{
    'format': format,
    'width': width,
    'height': height,
    'pixels': pixels,
    'gpsPresent': gpsPresent,
    'metadataContainerPresent': metadataContainerPresent,
  };
}

Future<AcceptanceImageMetadata> inspectAcceptanceImage(String path) async {
  final bytes = await File(path).readAsBytes();
  final decoder = image.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null) {
    throw const FormatException('Unsupported or corrupt image.');
  }

  final format = _detectFormat(bytes);
  var gpsPresent = false;
  var metadataContainerPresent = false;

  if (format == 'JPEG') {
    final exif = image.decodeJpgExif(bytes);
    metadataContainerPresent = exif != null && !exif.isEmpty;
    gpsPresent = exif != null && exif.gpsIfd.data.isNotEmpty;
  } else if (format == 'PNG') {
    final result = _inspectPngMetadata(bytes);
    metadataContainerPresent = result.metadataContainerPresent;
    gpsPresent = result.gpsPresent;
  }

  return AcceptanceImageMetadata(
    format: format,
    width: info.width,
    height: info.height,
    gpsPresent: gpsPresent,
    metadataContainerPresent: metadataContainerPresent,
  );
}

String _detectFormat(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'PNG';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'JPEG';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'WEBP';
  }
  return 'OTHER';
}

_PngMetadataResult _inspectPngMetadata(Uint8List bytes) {
  var offset = 8;
  var metadataContainerPresent = false;
  var gpsPresent = false;

  while (offset + 12 <= bytes.length) {
    final length = ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).getUint32(0, Endian.big);
    final typeStart = offset + 4;
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    final next = dataEnd + 4;
    if (dataEnd > bytes.length || next > bytes.length) {
      throw const FormatException('Invalid PNG chunk length.');
    }

    final type = ascii.decode(
      bytes.sublist(typeStart, dataStart),
      allowInvalid: true,
    );
    final data = bytes.sublist(dataStart, dataEnd);
    if (type == 'eXIf') {
      metadataContainerPresent = true;
      try {
        final exif = image.ExifData.fromInputBuffer(image.InputBuffer(data));
        gpsPresent = gpsPresent || exif.gpsIfd.data.isNotEmpty;
      } on Object {
        // A malformed metadata container is still metadata. The output
        // acceptance rejects it through metadataContainerPresent.
      }
    } else if (type == 'tEXt' || type == 'iTXt' || type == 'zTXt') {
      metadataContainerPresent = true;
      final text = latin1.decode(data, allowInvalid: true).toLowerCase();
      gpsPresent =
          gpsPresent ||
          text.contains('gpslatitude') ||
          text.contains('gpslongitude') ||
          text.contains('gpsposition') ||
          text.contains('exif:gps');
    }

    offset = next;
    if (type == 'IEND') break;
  }

  return _PngMetadataResult(
    gpsPresent: gpsPresent,
    metadataContainerPresent: metadataContainerPresent,
  );
}

final class _PngMetadataResult {
  const _PngMetadataResult({
    required this.gpsPresent,
    required this.metadataContainerPresent,
  });

  final bool gpsPresent;
  final bool metadataContainerPresent;
}
