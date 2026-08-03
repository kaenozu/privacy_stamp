import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'features/redaction/models/redaction_models.dart';
import 'features/redaction/presentation/stamp_controller.dart';

void main() => runApp(const PrivacyStampApp());

class PrivacyStampApp extends StatelessWidget {
  const PrivacyStampApp({super.key, this.home});

  final Widget? home;

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
    home: home ?? const StampHomePage(),
  );
}

class StampHomePage extends StatefulWidget {
  const StampHomePage({super.key, this.controller});

  final StampController? controller;

  @override
  State<StampHomePage> createState() => _StampHomePageState();
}

class _StampHomePageState extends State<StampHomePage> {
  late final StampController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? StampController.defaults();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    final result = await _controller.exportImage();
    if (!mounted) return;
    switch (result) {
      case ExportResult.exported:
        _notice('元画像とは別のPNGを書き出しました。メタデータは引き継ぎません。');
      case ExportResult.cancelled:
      case ExportResult.busy:
      case ExportResult.stale:
        break;
      case ExportResult.unavailable:
        _notice('隠す領域を追加してください');
      case ExportResult.failed:
        _notice('書き出しに失敗しました。画像を確認して再試行してください。');
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Privacy Stamp'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(child: Text('書き出し履歴 ${_controller.exportCount}件')),
        ),
      ],
    ),
    body: _controller.hasImage
        ? _Editor(
            bytes: _controller.bytes!,
            imageSize: _controller.imageSize!,
            stamps: _controller.stamps,
            manualStamps: _controller.manualStamps,
            busy: _controller.isBusy,
            onAdd: _controller.addManualStamp,
            onAddAt: _controller.addManualStampAt,
            onMove: _controller.moveManualStamp,
            onResize: _controller.resizeManualStamp,
            onRemove: _controller.removeManualStamp,
            onExport: _export,
            onReset: _controller.reset,
          )
        : _Picker(onPick: _controller.pickImage, busy: _controller.isBusy),
  );

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.onPick, required this.busy});

  final VoidCallback onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
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
                Semantics(
                  button: true,
                  label: '画像を選ぶ',
                  child: FilledButton.icon(
                    onPressed: busy ? null : onPick,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('画像を選ぶ'),
                  ),
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
    ),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({
    required this.bytes,
    required this.imageSize,
    required this.stamps,
    required this.manualStamps,
    required this.busy,
    required this.onAdd,
    required this.onAddAt,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
    required this.onExport,
    required this.onReset,
  });

  final Uint8List bytes;
  final PixelSize imageSize;
  final List<Stamp> stamps;
  final List<Stamp> manualStamps;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<ui.Offset> onAddAt;
  final void Function(String id, ui.Offset delta) onMove;
  final void Function(String id, ui.Offset delta) onResize;
  final ValueChanged<String> onRemove;
  final VoidCallback onExport;
  final VoidCallback onReset;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  String? _selectedStampId;

  @override
  void didUpdateWidget(covariant _Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedStampId != null &&
        !widget.manualStamps.any((stamp) => stamp.id == _selectedStampId)) {
      _selectedStampId = null;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(context),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(1.0, 640.0).toDouble();
              final height = width.clamp(240.0, 520.0).toDouble();
              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: AbsorbPointer(
                    absorbing: widget.busy,
                    child: _ImageEditorCanvas(
                      key: const ValueKey('image-editor-canvas'),
                      bytes: widget.bytes,
                      imageSize: widget.imageSize,
                      stamps: widget.stamps,
                      selectedStampId: _selectedStampId,
                      onSelect: (stamp) =>
                          setState(() => _selectedStampId = stamp.id),
                      onAddAt: widget.onAddAt,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          if (_selectedStampId != null &&
              widget.manualStamps.any((s) => s.id == _selectedStampId))
            _buildSelectedControls(context),
          if (widget.busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _buildFooter(context),
        ],
      ),
    ),
  );

  Widget _buildToolbar(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '自動検出は未実装です。OCR・顔・バーコードの領域は追加されません。手動でマスクしてください。',
            semanticsLabel: '自動検出は未実装です。手動でマスクしてください。',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onAdd,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('手動スタンプを追加'),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onReset,
                icon: const Icon(Icons.close),
                label: const Text('別の画像'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildSelectedControls(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('選択中の手動マスク'),
          _controlButton('左へ', Icons.arrow_back, () {
            widget.onMove(_selectedStampId!, const ui.Offset(-.03, 0));
          }),
          _controlButton('右へ', Icons.arrow_forward, () {
            widget.onMove(_selectedStampId!, const ui.Offset(.03, 0));
          }),
          _controlButton('上へ', Icons.arrow_upward, () {
            widget.onMove(_selectedStampId!, const ui.Offset(0, -.03));
          }),
          _controlButton('下へ', Icons.arrow_downward, () {
            widget.onMove(_selectedStampId!, const ui.Offset(0, .03));
          }),
          _controlButton('大きく', Icons.zoom_in, () {
            widget.onResize(_selectedStampId!, const ui.Offset(.03, .03));
          }),
          _controlButton('小さく', Icons.zoom_out, () {
            widget.onResize(_selectedStampId!, const ui.Offset(-.03, -.03));
          }),
          _controlButton('削除', Icons.delete_outline, () {
            widget.onRemove(_selectedStampId!);
            setState(() => _selectedStampId = null);
          }),
        ],
      ),
    ),
  );

  Widget _controlButton(String label, IconData icon, VoidCallback onPressed) =>
      Semantics(
        button: true,
        label: '選択中のマスクを$label',
        child: TextButton.icon(
          onPressed: widget.busy ? null : onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );

  Widget _buildFooter(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 8,
    children: [
      Text(
        '${widget.stamps.length} 件のマスク',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      FilledButton.icon(
        onPressed: widget.busy ? null : widget.onExport,
        icon: const Icon(Icons.save_alt),
        label: const Text('書き出す'),
      ),
    ],
  );
}

class _ImageEditorCanvas extends StatelessWidget {
  const _ImageEditorCanvas({
    super.key,
    required this.bytes,
    required this.imageSize,
    required this.stamps,
    required this.selectedStampId,
    required this.onSelect,
    required this.onAddAt,
  });

  final Uint8List bytes;
  final PixelSize imageSize;
  final List<Stamp> stamps;
  final String? selectedStampId;
  final ValueChanged<Stamp> onSelect;
  final ValueChanged<ui.Offset> onAddAt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final canvasSize = ui.Size(constraints.maxWidth, constraints.maxHeight);
      final layout = ImageDisplayLayout.contain(
        imageSize: imageSize,
        canvasSize: canvasSize,
      );
      return Semantics(
        label: '画像編集領域。画像上をタップすると手動マスクを追加します。',
        container: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (!layout.imageRect.contains(details.localPosition)) return;
            final normalized = layout.normalizedRectFromDisplay(
              ui.Rect.fromCenter(
                center: details.localPosition,
                width: 0,
                height: 0,
              ),
            );
            onAddAt(ui.Offset(normalized.left, normalized.top));
          },
          child: ColoredBox(
            color: Colors.black12,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Text('画像を表示できません')),
                ),
                for (final stamp in stamps)
                  _StampOverlay(
                    stamp: stamp,
                    rect: layout.displayRectFromNormalized(stamp.rect),
                    selected: stamp.id == selectedStampId,
                    onSelect: () => onSelect(stamp),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _StampOverlay extends StatelessWidget {
  const _StampOverlay({
    required this.stamp,
    required this.rect,
    required this.selected,
    required this.onSelect,
  });

  final Stamp stamp;
  final ui.Rect rect;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: rect,
    child: Semantics(
      button: true,
      label: '${stamp.isAutomatic ? '自動' : '手動'}マスク${selected ? '、選択中' : ''}',
      hint: 'タップして操作対象に選択',
      onTap: onSelect,
      child: GestureDetector(
        onTap: onSelect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: stamp.kind == 'white' ? Colors.white : Colors.black,
            border: Border.all(
              color: selected ? Colors.lightBlueAccent : Colors.orange,
              width: selected ? 3 : 2,
            ),
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
    ),
  );
}
