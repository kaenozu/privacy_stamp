import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_stamp/features/redaction/models/redaction_models.dart';

void main() {
  test('computes the actual BoxFit.contain image rect and canvas padding', () {
    final square = ImageDisplayLayout.contain(
      imageSize: const PixelSize(100, 100),
      canvasSize: const Size(200, 300),
    );
    expect(square.imageRect, const Rect.fromLTWH(0, 50, 200, 200));
    expect(
      square.padding,
      const CanvasPadding(left: 0, top: 50, right: 0, bottom: 50),
    );

    final landscape = ImageDisplayLayout.contain(
      imageSize: const PixelSize(200, 100),
      canvasSize: const Size(300, 300),
    );
    expect(landscape.imageRect, const Rect.fromLTWH(0, 75, 300, 150));
    expect(landscape.padding.top, 75);
    expect(landscape.padding.bottom, 75);

    final portrait = ImageDisplayLayout.contain(
      imageSize: const PixelSize(100, 200),
      canvasSize: const Size(300, 300),
    );
    expect(portrait.imageRect, const Rect.fromLTWH(75, 0, 150, 300));
    expect(portrait.padding.left, 75);
    expect(portrait.padding.right, 75);
  });

  test('converts normalized and display rectangles in both directions', () {
    final layout = ImageDisplayLayout.contain(
      imageSize: const PixelSize(200, 100),
      canvasSize: const Size(300, 300),
    );
    const normalized = NormalizedRect(.2, .1, .5, .6);

    expect(
      layout.displayRectFromNormalized(normalized),
      const Rect.fromLTWH(60, 90, 150, 90),
    );
    expect(
      layout.normalizedRectFromDisplay(const Rect.fromLTWH(60, 90, 150, 90)),
      normalized,
    );
  });

  test(
    'clamps normalized rectangles and exposes a one-pixel minimum contract',
    () {
      final layout = ImageDisplayLayout.contain(
        imageSize: const PixelSize(4, 8),
        canvasSize: const Size(200, 200),
      );
      final clamped = layout.clampNormalizedRect(
        const NormalizedRect(-.25, .75, 1.5, .5),
      );
      expect(clamped.left, 0);
      expect(clamped.top, .75);
      expect(clamped.width, 1);
      expect(clamped.height, .25);
      expect(
        layout.normalizedRectHasMinimumPixelSize(
          const NormalizedRect(.25, .25, .25, .125),
        ),
        isTrue,
      );
      expect(
        layout.normalizedRectHasMinimumPixelSize(
          const NormalizedRect(.25, .25, .2, .125),
        ),
        isFalse,
      );
      expect(
        layout.pixelRectFromNormalized(
          const NormalizedRect(.25, .25, .25, .125),
        ),
        const PixelRect(1, 2, 1, 1),
      );
    },
  );

  test('reports rotated dimensions used after EXIF orientation is baked', () {
    const source = PixelSize(640, 480);
    expect(ExifOrientation.orientedSize(source, 3), source);
    expect(ExifOrientation.orientedSize(source, 6), const PixelSize(480, 640));
    expect(ExifOrientation.orientedSize(source, 8), const PixelSize(480, 640));
  });

  test('rejects non-positive dimensions in the coordinate contract', () {
    expect(
      () => ImageDisplayLayout.contain(
        imageSize: const PixelSize(0, 100),
        canvasSize: const Size(200, 200),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ImageDisplayLayout.contain(
        imageSize: const PixelSize(100, 100),
        canvasSize: const Size(0, 200),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
