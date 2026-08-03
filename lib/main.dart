import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/redaction/detection/detector_service.dart';
import 'features/redaction/export/redaction_exporter.dart';
import 'features/redaction/models/redaction_models.dart';

void main() => runApp(const PrivacyStampApp());

class PrivacyStampApp extends StatelessWidget {
  const PrivacyStampApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Privacy Stamp',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff315c72),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    ),
    home: const StampHomePage(),
  );
}

class StampHomePage extends StatefulWidget {
  const StampHomePage({super.key});
  @override
  State<StampHomePage> createState() => _StampHomePageState();
}

class _StampHomePageState extends State<StampHomePage> {
  Uint8List? _bytes;
  String? _fileName;
  bool _busy = false;
  bool _strongMode = false;
  List<Stamp> _stamps = [];
  int _exports = 0;
  final _detector = DetectionService();
  final _exporter = RedactionExporter();

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final data = result?.files.single.bytes;
    if (data == null) return;
    setState(() {
      _bytes = data;
      _fileName = result!.files.single.name;
      _stamps = [];
      _busy = true;
    });
    final detections = await _detector.inspect(
      Uint8ListImageInput(data),
      hideAllText: _strongMode,
    );
    if (!mounted) return;
    setState(() {
      _stamps = detections
          .map(
            (d) => Stamp(id: d.id, rect: d.normalizedRect, isAutomatic: true),
          )
          .toList();
      _busy = false;
    });
  }

  void _addStamp() => setState(
    () => _stamps.add(
      Stamp(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        rect: const NormalizedRect(.35, .35, .3, .16),
      ),
    ),
  );
  void _remove(String id) =>
      setState(() => _stamps.removeWhere((s) => s.id == id));
  void _toggleStrong(bool value) {
    setState(() => _strongMode = value);
    if (_bytes != null) _pick();
  }

  Future<void> _export() async {
    if (_bytes == null || _stamps.isEmpty) {
      _notice('隠す領域を追加してください');
      return;
    }
    setState(() => _busy = true);
    try {
      final output = _exporter.encode(_bytes!, _stamps);
      final path = await FilePicker.platform.saveFile(
        fileName: 'privacy-stamped-${_fileName ?? 'image'}.png',
        bytes: output,
      );
      if (path != null) {
        final prefs = await SharedPreferences.getInstance();
        final count = prefs.getInt('export_count') ?? 0;
        await prefs.setInt('export_count', count + 1);
        setState(() => _exports = count + 1);
        _notice('元画像とは別のPNGを書き出しました。メタデータは引き継ぎません。');
      }
    } catch (error) {
      _notice('書き出しに失敗しました: $error');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _exports = p.getInt('export_count') ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Privacy Stamp'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(child: Text('無料書き出し $_exports / 3')),
        ),
      ],
    ),
    body: _bytes == null
        ? _Picker(onPick: _pick)
        : _Editor(
            bytes: _bytes!,
            stamps: _stamps,
            busy: _busy,
            strongMode: _strongMode,
            onStrongMode: _toggleStrong,
            onAdd: _addStamp,
            onRemove: _remove,
            onExport: _export,
            onReset: () => setState(() {
              _bytes = null;
              _stamps = [];
            }),
          ),
  );
}

class _Picker extends StatelessWidget {
  const _Picker({required this.onPick});
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.privacy_tip_outlined, size: 64),
              const SizedBox(height: 20),
              Text(
                '公開前に、画像の個人情報を隠します',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                '画像は端末・ブラウザー内で処理されます。サーバーへ送信しません。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.image_outlined),
                label: const Text('画像を選ぶ'),
              ),
              const SizedBox(height: 12),
              const Text(
                'JPEG / PNG / WebP ・画像は1枚ずつ',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.bytes,
    required this.stamps,
    required this.busy,
    required this.strongMode,
    required this.onStrongMode,
    required this.onAdd,
    required this.onRemove,
    required this.onExport,
    required this.onReset,
  });
  final Uint8List bytes;
  final List<Stamp> stamps;
  final bool busy;
  final bool strongMode;
  final ValueChanged<bool> onStrongMode;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onExport;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                FilterChip(
                  label: const Text('文字をすべて隠す'),
                  selected: strongMode,
                  onSelected: onStrongMode,
                ),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('手動スタンプ'),
                ),
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.close),
                  label: const Text('別の画像'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes, fit: BoxFit.contain),
                    for (final stamp in stamps)
                      _StampOverlay(
                        stamp: stamp,
                        onRemove: () => onRemove(stamp.id),
                        size: box.biggest,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stamps.length} 件のマスク',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FilledButton.icon(
                onPressed: busy ? null : onExport,
                icon: const Icon(Icons.save_alt),
                label: const Text('書き出す'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StampOverlay extends StatelessWidget {
  const _StampOverlay({
    required this.stamp,
    required this.onRemove,
    required this.size,
  });
  final Stamp stamp;
  final VoidCallback onRemove;
  final Size size;
  @override
  Widget build(BuildContext context) {
    final r = stamp.rect;
    return Positioned(
      left: r.left * size.width,
      top: r.top * size.height,
      width: r.width * size.width,
      height: r.height * size.height,
      child: GestureDetector(
        onLongPress: onRemove,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: stamp.kind == 'white' ? Colors.white : Colors.black,
            border: Border.all(color: Colors.orange, width: 2),
          ),
          child: Center(
            child: Text(
              stamp.isAutomatic ? '自動' : '手動',
              style: TextStyle(
                color: stamp.kind == 'white' ? Colors.black : Colors.white,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
