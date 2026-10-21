import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/app_product.dart';
import 'browser_bookmark_store.dart';

/// Wallpaper appearance shared by the HTML home page and native tab overview.
abstract final class BrowserBackgroundStyle {
  static const colours = AppProduct.ambulando
      ? [0xffdbe8dd, 0xffe9ede2, 0xffc5dbd5]
      : [0xff291c3d, 0xff513568, 0xff7040aa];
  static const tint = AppProduct.ambulando ? 0x55edf4e7 : 0x33291c3d;
  static String get gradientCss {
    final css = colours
        .map((c) => '#${(c & 0xffffff).toRadixString(16).padLeft(6, '0')}')
        .toList();
    return 'linear-gradient(145deg,${css[0]},${css[1]} 55%,${css[2]})';
  }

  static String get tintCss =>
      '#${(tint & 0xffffff).toRadixString(16).padLeft(6, '0')}${(tint >> 24).toRadixString(16).padLeft(2, '0')}';
}

class BrowserBackground extends StatelessWidget {
  const BrowserBackground(
      {super.key, required this.image, required this.child});
  final String? image;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final safeImage = safeBookmarkImage(image);
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
        begin: const Alignment(-0.7, -1),
        end: const Alignment(0.7, 1),
        stops: const [0, 0.55, 1],
        colors: BrowserBackgroundStyle.colours.map(Color.new).toList(),
      ))),
      if (safeImage != null)
        Image.memory(
          base64Decode(safeImage.substring(22)),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          excludeFromSemantics: true,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
        ),
      if (safeImage != null)
        const ColoredBox(color: Color(BrowserBackgroundStyle.tint)),
      child,
    ]);
  }
}
