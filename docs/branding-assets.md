# WMApp branding assets

WMApp uses the approved wayfinder hybrid: a purple compass and wing with an
orange direction marker on white. The source is retained unchanged at
`app/assets/branding/wayfinder-hybrid.png` (1254 × 1254 RGB PNG).
Its SHA-256 is
`4d647569a15b0d20a8392b615fdaf2029dbdcec48342a2a874667cfc310a5cc2`.
Exports resize or pad that approved image; they do not redraw the artwork.

Run from the repository root with Python 3 and ImageMagick 7 installed:

```sh
python3 tools/branding_assets.py
python3 tools/branding_assets.py --check
```

The checked export toolchain is ImageMagick 7.1.2-8 Q16-HDRI.

The check verifies actual PNG signatures, RGB format and dimensions, ICO frame
sizes, manifest MIME types and purposes, and that coloured maskable pixels stay
inside the 80%-diameter safe circle. It regenerates exports in a temporary directory, compares their bytes,
and checks manifest dimensions, web entry references and Apple asset catalogs.
Use the same ImageMagick version for byte comparison; resampling differences
between versions can require reviewing and regenerating the exports.

| Surface | Assets |
| --- | --- |
| Public documentation | `public/logo.png`, 512 × 512 |
| Flutter interface | `app/assets/branding/wmapp-logo.png`, 512 × 512 |
| Public and Flutter web favicons | 16, 32, 48 PNG; ICO containing all three; `favicon.png` 32 |
| Apple touch icon | 180 × 180 |
| Web manifests | 192 and 512 normal and separate maskable PNGs |
| Android launchers | 48, 72, 96, 144, 192 for mdpi through xxxhdpi |
| iOS | Existing AppIcon catalog, including 1024 App Store image; launch logo 60/120/180 |
| macOS | Existing AppIcon catalog, 16 through 1024 |
| Linux | 256 icon installed as `data/wmapp.png` and loaded by GTK relative to the executable |

Maskable exports place the complete approved square at 70% of the canvas width
and centre it on white. The coloured mark stays within the central safe circle
with diameter 80% of the output. Normal exports preserve the approved framing.
All generated PNGs are opaque RGB, including the iOS store icon.

The `public/` directory is a reusable publication asset set; the Flutter build
serves `app/web/`. Both manifests point to their own relative icon paths.
There is no Windows runner in this repository, so no Windows application icon
is claimed. The ICO files are browser favicons.
The separate Ambulando iOS icon and launch resources remain its own branding.
Internal bundle identifiers, repository and binary names retain their existing
values; product display labels use WMApp (WMApp Nightly for Android nightlies).

For visual review, inspect normal and maskable exports at native 16/32/48 sizes,
at 180/192 and 512, and against both light and dark surroundings. Confirm the
compass, wing and orange marker match the master, and maskable crops keep the
mark intact. Platform build and runtime checks remain necessary: this audit
checks asset files and references, not OS launcher caches or installed apps.
