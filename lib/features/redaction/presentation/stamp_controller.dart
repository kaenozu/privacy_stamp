import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../detection/detector_service.dart';
import '../export/redaction_exporter.dart';
import '../models/redaction_models.dart';

abstract interface class ImagePickerGateway {
  Future<PickedImage?> pick();
}

abstract interface class ImageSaverGateway {
  Future<bool> save(Uint8List bytes, {required String fileName});
}

abstract interface class DetectionGateway {
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input);
}

abstract interface class ExportHistoryGateway {
  Future<int> readCount();
  Future<void> recordExport();
}

class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.name,
    required this.imageSize,
  });

  final List<int> bytes;
  final String name;
  final PixelSize imageSize;
}

class FilePickerImageGateway implements ImagePickerGateway {
  @override
  Future<PickedImage?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return null;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('画像を読み込めませんでした');
    }
    final oriented = img.bakeOrientation(decoded);
    return PickedImage(
      bytes: bytes,
      name: file!.name,
      imageSize: PixelSize(oriented.width, oriented.height),
    );
  }
}

class FilePickerImageSaver implements ImageSaverGateway {
  @override
  Future<bool> save(Uint8List bytes, {required String fileName}) async =>
      await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes) !=
      null;
}

class DetectionServiceGateway implements DetectionGateway {
  DetectionServiceGateway({DetectionService? detector})
    : _detector = detector ?? DetectionService();

  final DetectionService _detector;

  @override
  Future<List<DetectionRegion>> inspect(Uint8ListImageInput input) =>
      _detector.inspect(input);
}

class SharedPreferencesExportHistory implements ExportHistoryGateway {
  static const _key = 'export_count';

  @override
  Future<int> readCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  @override
  Future<void> recordExport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, (prefs.getInt(_key) ?? 0) + 1);
  }
}

enum ExportResult { exported, cancelled, unavailable, busy, failed, stale }

class StampController extends ChangeNotifier {
  StampController({
    required this.picker,
    required this.detector,
    required this.exporter,
    required this.saver,
    required this.history,
  }) {
    _loadHistory();
  }

  factory StampController.defaults() => StampController(
    picker: FilePickerImageGateway(),
    detector: DetectionServiceGateway(),
    exporter: RedactionExporter().encode,
    saver: FilePickerImageSaver(),
    history: SharedPreferencesExportHistory(),
  );

  final ImagePickerGateway picker;
  final DetectionGateway detector;
  final Uint8List Function(Uint8List source, List<Stamp> stamps) exporter;
  final ImageSaverGateway saver;
  final ExportHistoryGateway history;

  Uint8List? _bytes;
  String? _fileName;
  PixelSize? _imageSize;
  List<DetectionRegion> _detections = const [];
  List<Stamp> _manualStamps = const [];
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  int _exportCount = 0;

  Uint8List? get bytes => _bytes;
  String? get fileName => _fileName;
  PixelSize? get imageSize => _imageSize;
  bool get hasImage => _bytes != null;
  bool get isBusy => _busy;
  int get exportCount => _exportCount;
  List<DetectionRegion> get detections => List.unmodifiable(_detections);
  List<Stamp> get manualStamps => List.unmodifiable(_manualStamps);
  List<Stamp> get stamps => [
    for (final detection in _detections)
      if (detection.isEnabled)
        Stamp(
          id: detection.id,
          rect: detection.normalizedRect,
          isAutomatic: true,
        ),
    ..._manualStamps,
  ];

  Future<void> _loadHistory() async {
    try {
      final count = await history.readCount();
      if (_disposed) return;
      _exportCount = count;
      notifyListeners();
    } catch (_) {
      // History is informational only. A storage failure must not block editing.
    }
  }

  Future<void> pickImage() async {
    if (_busy || _disposed) return;
    final token = ++_generation;
    _busy = true;
    notifyListeners();
    try {
      final picked = await picker.pick();
      if (!_isCurrent(token) || picked == null) return;

      _bytes = Uint8List.fromList(picked.bytes);
      _fileName = picked.name;
      _imageSize = picked.imageSize;
      _detections = const [];
      _manualStamps = const [];
      notifyListeners();

      final detections = await detector.inspect(Uint8ListImageInput(_bytes!));
      if (!_isCurrent(token)) return;
      _detections = List.unmodifiable(detections);
    } catch (_) {
      // The UI reports a generic retryable message; internal exception details
      // never become user-facing text.
    } finally {
      if (_isCurrent(token)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void addManualStamp() => addManualStampAt(const Offset(.5, .5));

  void addManualStampAt(Offset normalizedCenter) {
    if (_disposed || _busy || !hasImage) return;
    const width = .3;
    const height = .16;
    final rect = NormalizedRect(
      normalizedCenter.dx - width / 2,
      normalizedCenter.dy - height / 2,
      width,
      height,
    ).clamp();
    _manualStamps = [
      ..._manualStamps,
      Stamp(id: 'manual-${DateTime.now().microsecondsSinceEpoch}', rect: rect),
    ];
    notifyListeners();
  }

  void moveManualStamp(String id, Offset delta) {
    if (_disposed || _busy) return;
    final stamp = _findManualStamp(id);
    if (stamp == null) return;
    final rect = stamp.rect;
    stamp.rect = NormalizedRect(
      (rect.left + delta.dx).clamp(0.0, 1.0 - rect.width).toDouble(),
      (rect.top + delta.dy).clamp(0.0, 1.0 - rect.height).toDouble(),
      rect.width,
      rect.height,
    );
    notifyListeners();
  }

  void resizeManualStamp(String id, Offset delta) {
    if (_disposed || _busy) return;
    final stamp = _findManualStamp(id);
    if (stamp == null) return;
    final rect = stamp.rect;
    final width = (rect.width + delta.dx)
        .clamp(.05, 1.0 - rect.left)
        .toDouble();
    final height = (rect.height + delta.dy)
        .clamp(.04, 1.0 - rect.top)
        .toDouble();
    stamp.rect = NormalizedRect(rect.left, rect.top, width, height);
    notifyListeners();
  }

  void removeManualStamp(String id) {
    if (_disposed || _busy) return;
    final before = _manualStamps.length;
    _manualStamps = _manualStamps.where((stamp) => stamp.id != id).toList();
    if (_manualStamps.length != before) notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    ++_generation;
    _bytes = null;
    _fileName = null;
    _imageSize = null;
    _detections = const [];
    _manualStamps = const [];
    _busy = false;
    notifyListeners();
  }

  Future<ExportResult> exportImage() async {
    if (_disposed) return ExportResult.stale;
    if (_busy) return ExportResult.busy;
    final bytes = _bytes;
    final stamps = this.stamps;
    if (bytes == null || stamps.isEmpty) return ExportResult.unavailable;

    final token = _generation;
    _busy = true;
    notifyListeners();
    try {
      final output = exporter(bytes, stamps);
      final saved = await saver.save(
        output,
        fileName: 'privacy-stamped-${_fileName ?? 'image'}.png',
      );
      if (!_isCurrent(token)) return ExportResult.stale;
      if (!saved) return ExportResult.cancelled;
      try {
        await history.recordExport();
      } catch (_) {
        // Export history is not part of the image-save result.
      }
      if (!_isCurrent(token)) return ExportResult.stale;
      _exportCount++;
      return ExportResult.exported;
    } catch (_) {
      return ExportResult.failed;
    } finally {
      if (_isCurrent(token)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Stamp? _findManualStamp(String id) {
    for (final stamp in _manualStamps) {
      if (stamp.id == id) return stamp;
    }
    return null;
  }

  bool _isCurrent(int token) => !_disposed && token == _generation;

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
