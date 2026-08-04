import 'dart:math' as math;
import 'dart:ui';

/// A positive-or-zero image dimension expressed in physical pixels.
///
/// The fields intentionally remain [int]. Normalized coordinates are kept as
/// [double] values in [NormalizedRect] and are converted only at a boundary.
class PixelSize {
  const PixelSize(this.width, this.height);

  final int width;
  final int height;

  bool get isPositive => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is PixelSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width x $height px';
}

/// An integer rectangle in image pixels.
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  bool get isPositive => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PixelRect($left, $top, $width, $height)';
}

/// The four areas of a display canvas not occupied by the contained image.
class CanvasPadding {
  const CanvasPadding({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is CanvasPadding &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// The result of laying an image into a canvas with [BoxFit.contain] rules.
///
/// [imageRect] is the actual displayed image rectangle. It excludes the
/// letterbox/pillarbox padding, so normalized stamp coordinates never include
/// the canvas margins.
class ImageDisplayLayout {
  ImageDisplayLayout._({
    required this.imageSize,
    required this.canvasSize,
    required this.imageRect,
    required this.padding,
  });

  factory ImageDisplayLayout.contain({
    required PixelSize imageSize,
    required Size canvasSize,
  }) {
    _requirePositiveImageSize(imageSize);
    if (!_isFinitePositive(canvasSize.width) ||
        !_isFinitePositive(canvasSize.height)) {
      throw const FormatException('表示canvasのサイズが不正です');
    }

    final scale = math.min(
      canvasSize.width / imageSize.width,
      canvasSize.height / imageSize.height,
    );
    final displayedSize = Size(
      imageSize.width * scale,
      imageSize.height * scale,
    );
    final imageRect = Rect.fromLTWH(
      (canvasSize.width - displayedSize.width) / 2,
      (canvasSize.height - displayedSize.height) / 2,
      displayedSize.width,
      displayedSize.height,
    );

    return ImageDisplayLayout._(
      imageSize: imageSize,
      canvasSize: canvasSize,
      imageRect: imageRect,
      padding: CanvasPadding(
        left: imageRect.left,
        top: imageRect.top,
        right: canvasSize.width - imageRect.right,
        bottom: canvasSize.height - imageRect.bottom,
      ),
    );
  }

  final PixelSize imageSize;
  final Size canvasSize;
  final Rect imageRect;
  final CanvasPadding padding;

  /// Maps a normalized image rectangle into the display canvas.
  Rect displayRectFromNormalized(NormalizedRect normalized) {
    normalized.requireFinite();
    return Rect.fromLTWH(
      imageRect.left + normalized.left * imageRect.width,
      imageRect.top + normalized.top * imageRect.height,
      normalized.width * imageRect.width,
      normalized.height * imageRect.height,
    );
  }

  /// Maps a display-canvas rectangle into normalized image coordinates.
  ///
  /// The returned rectangle is not clamped. Use [clampNormalizedRect] after
  /// pointer/touch input that may fall into the canvas padding.
  NormalizedRect normalizedRectFromDisplay(Rect displayRect) {
    if (!_isFiniteRect(displayRect)) {
      throw const FormatException('表示rectのサイズが不正です');
    }
    return NormalizedRect(
      (displayRect.left - imageRect.left) / imageRect.width,
      (displayRect.top - imageRect.top) / imageRect.height,
      displayRect.width / imageRect.width,
      displayRect.height / imageRect.height,
    );
  }

  NormalizedRect clampNormalizedRect(NormalizedRect normalized) =>
      normalized.clamp();

  bool normalizedRectHasMinimumPixelSize(
    NormalizedRect normalized, {
    int minimumPixelSize = 1,
  }) {
    if (minimumPixelSize < 1 || !normalized.isWithinUnitSquare) return false;
    return normalized.width * imageSize.width >= minimumPixelSize &&
        normalized.height * imageSize.height >= minimumPixelSize;
  }

  /// Converts a valid normalized rectangle to an integer pixel rectangle.
  ///
  /// Edges use floor/ceil so every touched source pixel is covered. Invalid,
  /// out-of-range, zero-area, or sub-minimum rectangles throw instead of
  /// being silently enlarged or clipped.
  PixelRect pixelRectFromNormalized(
    NormalizedRect normalized, {
    int minimumPixelSize = 1,
  }) {
    normalized.requireWithinUnitSquare();
    if (!normalizedRectHasMinimumPixelSize(
      normalized,
      minimumPixelSize: minimumPixelSize,
    )) {
      throw const FormatException('マスクが1px未満です');
    }

    final left = (normalized.left * imageSize.width).floor();
    final top = (normalized.top * imageSize.height).floor();
    final right = (normalized.right * imageSize.width).ceil();
    final bottom = (normalized.bottom * imageSize.height).ceil();
    final result = PixelRect(left, top, right - left, bottom - top);
    if (!result.isPositive ||
        result.left < 0 ||
        result.top < 0 ||
        result.right > imageSize.width ||
        result.bottom > imageSize.height) {
      throw const FormatException('マスクのpixel範囲が不正です');
    }
    return result;
  }

  NormalizedRect normalizedRectFromPixels(PixelRect pixels) {
    if (!pixels.isPositive ||
        pixels.left < 0 ||
        pixels.top < 0 ||
        pixels.right > imageSize.width ||
        pixels.bottom > imageSize.height) {
      throw const FormatException('pixel rectの範囲が不正です');
    }
    return NormalizedRect(
      pixels.left / imageSize.width,
      pixels.top / imageSize.height,
      pixels.width / imageSize.width,
      pixels.height / imageSize.height,
    );
  }
}

class ExifOrientation {
  const ExifOrientation._();

  /// Returns the physical dimensions after [image] is baked for EXIF.
  static PixelSize orientedSize(PixelSize image, int orientation) {
    _requirePositiveImageSize(image);
    if (orientation < 1 || orientation > 8) {
      throw const FormatException('EXIF orientationが不正です');
    }
    return orientation >= 5 && orientation <= 8
        ? PixelSize(image.height, image.width)
        : image;
  }
}

class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  Rect get rect => Rect.fromLTWH(left, top, width, height);
  bool get isFinite =>
      left.isFinite && top.isFinite && width.isFinite && height.isFinite;
  bool get hasPositiveArea => width > 0 && height > 0;
  bool get isWithinUnitSquare =>
      isFinite &&
      left >= 0 &&
      top >= 0 &&
      width > 0 &&
      height > 0 &&
      right <= 1 &&
      bottom <= 1;

  void requireFinite() {
    if (!isFinite) throw const FormatException('正規化rectにNaN/infinityがあります');
  }

  void requireWithinUnitSquare() {
    requireFinite();
    if (!isWithinUnitSquare) {
      throw const FormatException('正規化rectが画像範囲外です');
    }
  }

  /// Clamps a finite rectangle by its edges into the normalized unit square.
  NormalizedRect clamp() {
    requireFinite();
    final clampedLeft = left.clamp(0.0, 1.0).toDouble();
    final clampedTop = top.clamp(0.0, 1.0).toDouble();
    final clampedRight = right.clamp(clampedLeft, 1.0).toDouble();
    final clampedBottom = bottom.clamp(clampedTop, 1.0).toDouble();
    return NormalizedRect(
      clampedLeft,
      clampedTop,
      clampedRight - clampedLeft,
      clampedBottom - clampedTop,
    );
  }

  NormalizedRect padded(double horizontal, double vertical) {
    if (!horizontal.isFinite ||
        !vertical.isFinite ||
        horizontal < 0 ||
        vertical < 0) {
      throw const FormatException('paddingのサイズが不正です');
    }
    return NormalizedRect(
      left - horizontal,
      top - vertical,
      width + horizontal * 2,
      height + vertical * 2,
    ).clamp();
  }

  @override
  bool operator ==(Object other) =>
      other is NormalizedRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'NormalizedRect($left, $top, $width, $height)';
}

bool _isFinitePositive(double value) => value.isFinite && value > 0;

bool _isFiniteRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.width.isFinite &&
    rect.height.isFinite;

void _requirePositiveImageSize(PixelSize imageSize) {
  if (!imageSize.isPositive) throw const FormatException('画像サイズが0pxです');
}
