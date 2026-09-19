import 'dart:convert';
import 'dart:io';
import 'dart:math' show cos, sin, pi, min, max;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

void main() => runApp(MaterialApp(
      title: 'Map Overlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const OverlayPage(),
    ));

/// JPG/PNG -> PNG. Runs in a background isolate (via compute) so the UI
/// does not freeze on large photos.
Uint8List? _toPng(String path) {
  var d = img.decodeImage(File(path).readAsBytesSync());
  if (d == null) return null;
  d = img.bakeOrientation(d); // phone photos: respect EXIF rotation
  const maxSide = 3000;
  if (d.width > maxSide || d.height > maxSide) {
    d = d.width >= d.height
        ? img.copyResize(d, width: maxSide)
        : img.copyResize(d, height: maxSide);
  }
  return Uint8List.fromList(img.encodePng(d));
}

String _xml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

class OverlayPage extends StatefulWidget {
  const OverlayPage({super.key});

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  final MapController _map = MapController();

  // Source file
  PdfDocument? _doc;
  int _page = 1;
  int _pageCount = 1;
  Uint8List? _png;
  double _imgW = 1, _imgH = 1;
  String _name = 'Overlay';

  // Placement
  LatLng? _topLeft;
  LatLng? _bottomRight;
  LatLng? _me;
  double _opacity = 0.7;
  double _rotation = 0; // degrees, counter-clockwise (same as KML)

  bool _busy = false;
  String _hint = 'Tap "Choose file" to pick a PDF or JPG';

  @override
  void dispose() {
    _doc?.close();
    _map.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------------
  // Current location
  // ------------------------------------------------------------------
  Future<void> _goToMyLocation({bool silent = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent) _toast('Please turn on location (GPS)');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!silent) _toast('Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _me = here);
      _map.move(here, 16);
    } catch (e) {
      if (!silent) _toast('Could not get location: $e');
    }
  }

  // ------------------------------------------------------------------
  // File -> PNG
  // ------------------------------------------------------------------
  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = res?.files.single.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      await _doc?.close();
      _doc = null;
      _page = 1;
      _pageCount = 1;

      Uint8List? png;
      if (path.toLowerCase().endsWith('.pdf')) {
        _doc = await PdfDocument.openFile(path);
        _pageCount = _doc!.pagesCount;
        png = await _renderPdfPage(1);
      } else {
        png = await compute(_toPng, path);
      }
      if (png == null) {
        _toast('Could not read this file');
        return;
      }

      final fileName = path.split(Platform.pathSeparator).last;
      _name = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      await _setImage(png);

      setState(() {
        _topLeft = null;
        _bottomRight = null;
        _rotation = 0;
        _hint = 'Tap the map where the image\'s top-left corner should be';
      });
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _renderPdfPage(int n) async {
    final page = await _doc!.getPage(n);
    try {
      // Keep the longest side around 3000 px at most
      final scale = min(2.0, 3000 / max(page.width, page.height));
      final r = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      return r?.bytes;
    } finally {
      await page.close();
    }
  }

  Future<void> _setImage(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final w = frame.image.width.toDouble();
    final h = frame.image.height.toDouble();
    frame.image.dispose();
    codec.dispose();
    if (!mounted) return;
    setState(() {
      _png = png;
      _imgW = w;
      _imgH = h;
    });
  }

  Future<void> _goToPage(int n) async {
    if (_doc == null || n < 1 || n > _pageCount || n == _page) return;
    setState(() => _busy = true);
    try {
      final png = await _renderPdfPage(n);
      if (png == null) return;
      _page = n;
      await _setImage(png);
      // Keep position and width, recompute height for the new page's ratio
      final tl = _topLeft, br = _bottomRight;
      if (tl != null && br != null) {
        setState(() => _bottomRight = _bottomRightFor(tl, br.longitude));
      }
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // Placement maths
  // ------------------------------------------------------------------

  /// Height follows from the image aspect ratio so the image is not stretched.
  LatLng _bottomRightFor(LatLng tl, double eastLon) {
    final dLon = eastLon - tl.longitude;
    final dLat = dLon * cos(tl.latitude * pi / 180) * _imgH / _imgW;
    return LatLng(tl.latitude - dLat, eastLon);
  }

  /// Corners (top-left, bottom-left, bottom-right) of the box rotated
  /// counter-clockwise by [deg] around its centre.
  List<LatLng> _rotatedCorners(LatLng tl, LatLng br, double deg) {
    final lat0 = (tl.latitude + br.latitude) / 2;
    final lon0 = (tl.longitude + br.longitude) / 2;
    final k = cos(lat0 * pi / 180);
    final hx = (br.longitude - tl.longitude) / 2 * k;
    final hy = (tl.latitude - br.latitude) / 2;
    final t = deg * pi / 180;

    LatLng rot(double x, double y) {
      final xr = x * cos(t) - y * sin(t);
      final yr = x * sin(t) + y * cos(t);
      return LatLng(lat0 + yr, lon0 + xr / k);
    }

    return [rot(-hx, hy), rot(-hx, -hy), rot(hx, -hy)];
  }

  void _onTap(TapPosition _, LatLng p) {
    if (_png == null) {
      _toast('Choose a file first');
      return;
    }
    final tl = _topLeft;

    // First tap (or start over)
    if (tl == null || _bottomRight != null) {
      setState(() {
        _topLeft = p;
        _bottomRight = null;
        _rotation = 0;
        _hint = 'Now tap where the image\'s right edge should be';
      });
      return;
    }

    // Second tap: sets width, height comes from aspect ratio
    if (p.longitude <= tl.longitude) {
      _toast('Tap to the right of the first point');
      return;
    }
    setState(() {
      _bottomRight = _bottomRightFor(tl, p.longitude);
      _hint = 'Adjust rotation / opacity, then Save KMZ. Tap map to start over.';
    });
  }

  void _reset() {
    setState(() {
      _topLeft = null;
      _bottomRight = null;
      _rotation = 0;
      _hint = _png == null
          ? 'Tap "Choose file" to pick a PDF or JPG'
          : 'Tap the map where the image\'s top-left corner should be';
    });
  }

  // ------------------------------------------------------------------
  // KMZ export
  // ------------------------------------------------------------------
  Future<void> _saveKmz() async {
    final tl = _topLeft, br = _bottomRight, png = _png;
    if (tl == null || br == null || png == null) {
      _toast('Place the image on the map first');
      return;
    }

    String f(double v) => v.toStringAsFixed(7);
    final alpha = (_opacity * 255).round().toRadixString(16).padLeft(2, '0');

    final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <GroundOverlay>
    <name>${_xml(_name)}</name>
    <color>${alpha}ffffff</color>
    <Icon><href>map.png</href></Icon>
    <LatLonBox>
      <north>${f(tl.latitude)}</north>
      <south>${f(br.latitude)}</south>
      <east>${f(br.longitude)}</east>
      <west>${f(tl.longitude)}</west>
      <rotation>${_rotation.toStringAsFixed(2)}</rotation>
    </LatLonBox>
  </GroundOverlay>
</kml>''';

    setState(() => _busy = true);
    try {
      final kmlBytes = utf8.encode(kml);
      final archive = Archive()
        ..addFile(ArchiveFile('doc.kml', kmlBytes.length, kmlBytes))
        ..addFile(ArchiveFile('map.png', png.length, png));
      final zipped = ZipEncoder().encode(archive)!;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_name.kmz');
      await file.writeAsBytes(zipped);

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.google-earth.kmz',
      );
      if (result.type == ResultType.noAppToOpen) {
        _toast('Google Earth is not installed');
      }
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  Widget _sliderRow(String label, double value, double lo, double hi,
      ValueChanged<double> onChanged, String valueText) {
    return Row(
      children: [
        SizedBox(width: 78, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: lo, max: hi, onChanged: onChanged),
        ),
        SizedBox(
          width: 46,
          child: Text(valueText, textAlign: TextAlign.end),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tl = _topLeft, br = _bottomRight, png = _png;
    final placed = png != null && tl != null && br != null;
    final corners = placed ? _rotatedCorners(tl, br, _rotation) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Overlay'),
        actions: [
          IconButton(
            tooltip: 'My location',
            icon: const Icon(Icons.my_location),
            onPressed: () => _goToMyLocation(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const LatLng(31.5497, 74.3436), // fallback
              initialZoom: 15,
              onTap: _onTap,
              onMapReady: () => _goToMyLocation(silent: true),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.map_overlay',
              ),
              if (placed)
                OverlayImageLayer(overlayImages: [
                  RotatedOverlayImage(
                    topLeftCorner: corners![0],
                    bottomLeftCorner: corners[1],
                    bottomRightCorner: corners[2],
                    opacity: _opacity,
                    imageProvider: MemoryImage(png),
                  ),
                ]),
              MarkerLayer(markers: [
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                if (tl != null && br == null)
                  Marker(
                    point: tl,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on,
                        color: Colors.red, size: 36),
                  ),
              ]),
            ],
          ),

          // OpenStreetMap attribution
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              color: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: const Text('© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10)),
            ),
          ),

          // Control panel
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: SafeArea(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_hint, textAlign: TextAlign.center),
                      if (_pageCount > 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _busy || _page <= 1
                                  ? null
                                  : () => _goToPage(_page - 1),
                            ),
                            Text('Page $_page / $_pageCount'),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _busy || _page >= _pageCount
                                  ? null
                                  : () => _goToPage(_page + 1),
                            ),
                          ],
                        ),
                      if (placed) ...[
                        _sliderRow(
                          'Rotation',
                          _rotation,
                          -180,
                          180,
                          (v) => setState(() => _rotation = v),
                          '${_rotation.round()}°',
                        ),
                        _sliderRow(
                          'Opacity',
                          _opacity,
                          0.2,
                          1.0,
                          (v) => setState(() => _opacity = v),
                          '${(_opacity * 100).round()}%',
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _pickFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Choose file'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy || tl == null ? null : _reset,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reset'),
                          ),
                          FilledButton.icon(
                            onPressed: _busy || !placed ? null : _saveKmz,
                            icon: const Icon(Icons.public),
                            label: const Text('Save KMZ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
