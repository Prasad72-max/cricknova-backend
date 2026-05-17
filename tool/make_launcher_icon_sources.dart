import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const sourcePath = 'assets/images/splash_player.png';
  const opaqueOutPath = 'assets/images/launcher_icon.png';
  const foregroundOutPath = 'assets/images/launcher_icon_foreground.png';
  const canvasSize = 1254;
  const logoSize = 820;

  final sourceFile = File(sourcePath);
  final source = img.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode $sourcePath');
    exitCode = 1;
    return;
  }

  final resized = img.copyResize(
    source,
    width: logoSize,
    height: logoSize,
    interpolation: img.Interpolation.cubic,
  );
  final offset = ((canvasSize - logoSize) / 2).round();

  final opaque = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  img.fill(opaque, color: img.ColorRgba8(0, 0, 0, 255));
  img.compositeImage(opaque, resized, dstX: offset, dstY: offset);

  final foreground = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  img.fill(foreground, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(foreground, resized, dstX: offset, dstY: offset);

  File(opaqueOutPath).writeAsBytesSync(img.encodePng(opaque, level: 6));
  File(foregroundOutPath).writeAsBytesSync(
    img.encodePng(foreground, level: 6),
  );

  stdout.writeln('Wrote $opaqueOutPath');
  stdout.writeln('Wrote $foregroundOutPath');
}
