from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text()
marker = 'class _ImageEditorCanvas extends StatelessWidget {'
head, sep, tail = text.partition(marker)
if not sep:
    raise SystemExit('image editor marker not found')
old_child = '        child: GestureDetector(\n'
new_child = """        child: InteractiveViewer(
          key: const ValueKey('image-editor-interactive-viewer'),
          minScale: 1,
          maxScale: 4,
          panEnabled: true,
          scaleEnabled: true,
          child: GestureDetector(
"""
if old_child not in tail:
    raise SystemExit('gesture child not found')
tail = tail.replace(old_child, new_child, 1)
end_marker = '\nclass _StampOverlay extends StatelessWidget {'
canvas, sep2, rest = tail.partition(end_marker)
if not sep2:
    raise SystemExit('stamp overlay marker not found')
old_end = '          ),\n        ),\n      );\n    },\n  );\n}\n'
new_end = '          ),\n        ),\n        ),\n      );\n    },\n  );\n}\n'
if old_end not in canvas:
    raise SystemExit('image editor closing sequence not found')
canvas = canvas.replace(old_end, new_end, 1)
path.write_text(head + sep + canvas + sep2 + rest)
