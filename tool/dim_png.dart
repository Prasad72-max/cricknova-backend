import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/dim_png.dart <factor 0-1> <png...>');
    exitCode = 64;
    return;
  }

  final factor = double.tryParse(args.first);
  if (factor == null || factor <= 0 || factor > 1) {
    stderr.writeln(
      'Invalid factor "${args.first}". Use a number between 0 and 1.',
    );
    exitCode = 64;
    return;
  }

  final paths = args.sublist(1);
  int processed = 0;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Skip (missing): $path');
      continue;
    }
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      stderr.writeln('Skip (unsupported image): $path');
      continue;
    }

    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final p = decoded.getPixel(x, y);
        final a = p.a;
        final r = (p.r * factor).round().clamp(0, 255);
        final g = (p.g * factor).round().clamp(0, 255);
        final b = (p.b * factor).round().clamp(0, 255);
        decoded.setPixelRgba(x, y, r, g, b, a);
      }
    }

    final out = img.encodePng(decoded, level: 6);
    file.writeAsBytesSync(out);
    processed++;
    stdout.writeln('Dimmed: $path');
  }

  stdout.writeln('Done. Processed $processed file(s).');
}
