import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A filename marker used to make the no-filename-inheritance assertion
/// explicit without putting a real person's name in the fixture.
const fixtureSourceFileName = 'fixture-test-only-gps-xmp.png';

Uint8List metadataBearingPng() {
  final image = img.Image(width: 2, height: 2, numChannels: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, 240, 180, 60, 255);
    }
  }

  final png = Uint8List.fromList(img.encodePng(image));
  final metadata = <Uint8List>[
    _pngChunk('eXIf', _exifGpsPayload()),
    _pngChunk(
      'iTXt',
      utf8.encode(
        'XML:com.adobe.xmp\u0000\u0000\u0000\u0000\u0000'
        '<x:xmpmeta><rdf:Description test-only-gps="12.34,56.78"/>'
        '</x:xmpmeta>',
      ),
    ),
    _pngChunk(
      'tEXt',
      ascii.encode(
        'Comment\u0000TEST-ONLY GPS=12.34,56.78;SourceFile=$fixtureSourceFileName',
      ),
    ),
  ];

  // IHDR is always the first chunk and has a 13-byte payload.
  const endOfIhdr = 8 + 4 + 4 + 13 + 4;
  return Uint8List.fromList([
    ...png.sublist(0, endOfIhdr),
    ...metadata.expand((chunk) => chunk),
    ...png.sublist(endOfIhdr),
  ]);
}

Uint8List rgbaPng() {
  final image = img.Image(width: 2, height: 1, numChannels: 4)
    ..setPixelRgba(0, 0, 220, 30, 40, 0)
    ..setPixelRgba(1, 0, 30, 220, 40, 96);
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List solidPng(int width, int height) {
  final image = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(40, 80, 120));
  return Uint8List.fromList(img.encodePng(image));
}

List<String> pngChunkTypes(Uint8List png) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  var hasSignature = png.length >= signature.length;
  for (var index = 0; hasSignature && index < signature.length; index++) {
    hasSignature = png[index] == signature[index];
  }
  if (!hasSignature) {
    throw const FormatException('Not a PNG');
  }

  final types = <String>[];
  var offset = signature.length;
  while (offset + 12 <= png.length) {
    final length = _readUint32(png, offset);
    final typeStart = offset + 4;
    final dataEnd = typeStart + 4 + length;
    final chunkEnd = dataEnd + 4;
    if (chunkEnd > png.length) {
      throw const FormatException('Truncated PNG chunk');
    }
    types.add(ascii.decode(png.sublist(typeStart, typeStart + 4)));
    offset = chunkEnd;
    if (types.last == 'IEND') break;
  }
  return types;
}

Uint8List _pngChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final crcInput = <int>[...typeBytes, ...data];
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32(crcInput)),
  ]);
}

List<int> _uint32(int value) => <int>[
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

int _readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (~crc) & 0xffffffff;
}

/// Minimal little-endian EXIF/TIFF data with GPSLatitudeRef and GPSLatitude.
List<int> _exifGpsPayload() {
  final bytes = <int>[
    0x49, 0x49, 0x2a, 0x00, // II, TIFF magic
    0x08, 0x00, 0x00, 0x00, // first IFD offset
    0x01, 0x00, // one IFD0 entry
    0x69, 0x87, 0x04, 0x00, // ExifIFDPointer, LONG
    0x01, 0x00, 0x00, 0x00, // one value
    0x1a, 0x00, 0x00, 0x00, // GPS IFD offset
    0x00, 0x00, 0x00, 0x00, // next IFD
    0x02, 0x00, // two GPS entries
    0x01, 0x00, 0x02, 0x00, // GPSLatitudeRef, ASCII
    0x02, 0x00, 0x00, 0x00, // two bytes
    0x4e, 0x00, 0x00, 0x00, // N\0, inline
    0x02, 0x00, 0x05, 0x00, // GPSLatitude, RATIONAL
    0x03, 0x00, 0x00, 0x00, // three values
    0x32, 0x00, 0x00, 0x00, // rational data offset
    0x23, 0x00, 0x00, 0x00, // 35/1
    0x01, 0x00, 0x00, 0x00,
    0x28, 0x00, 0x00, 0x00, // 40/1
    0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // 0/1
    0x01, 0x00, 0x00, 0x00,
  ];
  return bytes;
}
