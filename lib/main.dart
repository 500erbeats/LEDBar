import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LedApp());
}

class LedApp extends StatelessWidget {
  const LedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LEDBar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const SettingsPage(),
      );
}

// ───────────────────────── Nicht stören (nur Android) ─────────────────────────

class Dnd {
  static const _ch = MethodChannel('led_laufband/dnd');
  // Android: 1 = alles erlaubt, 2 = Prioritäts-Unterbrechungen, 3 = komplett still, 4 = nur Wecker
  static int? _previous;

  static bool get supported => Platform.isAndroid;

  static Future<bool> hasAccess() async =>
      supported && (await _ch.invokeMethod<bool>('hasAccess') ?? false);

  static Future<void> openSettings() => _ch.invokeMethod('openSettings');

  static Future<bool> enable() async {
    if (!await hasAccess()) return false;
    _previous = await _ch.invokeMethod<int>('getFilter');
    return await _ch.invokeMethod<bool>('setFilter', 3) ?? false;
  }

  static Future<void> restore() async {
    if (_previous == null || !await hasAccess()) return;
    await _ch.invokeMethod('setFilter', _previous);
    _previous = null;
  }
}

// ───────────────────────────── Einstellungen / Modell ─────────────────────────

const fonts = [
  'Orbitron',
  'Press Start 2P',
  'VT323',
  'Audiowide',
  'Bebas Neue',
  'Roboto Mono',
];

const bgSwatches = <int>[
  0xFF000000, // schwarz
  0xFFFFFFFF, // weiß
  0xFFFFD600, // gelb
  0xFFD50000, // rot
  0xFF0D47A1, // blau
  0xFF1B5E20, // grün
];

class LedSettings {
  final String text;
  final double hue; // 0-360
  final double saturation; // 0-1
  final double brightness; // 0.1-1
  final double speed; // px/s, 0 = stehend
  final double fontSize;
  final String font;
  final bool autoSize; // bei Tempo 0: Schrift passt sich dem Display an
  final bool rainbow;
  final bool leftToRight;
  final bool mirror;
  final int bgColor;
  final int blinkMode; // 0 aus, 1 blinken, 2 pulsieren
  final double blinkHz;
  final bool ledGrid;
  final double gridSize;

  const LedSettings({
    this.text = 'Hallo Welt 🎉',
    this.hue = 120,
    this.saturation = 1,
    this.brightness = 1,
    this.speed = 200,
    this.fontSize = 120,
    this.font = 'Orbitron',
    this.autoSize = false,
    this.rainbow = false,
    this.leftToRight = false,
    this.mirror = false,
    this.bgColor = 0xFF000000,
    this.blinkMode = 0,
    this.blinkHz = 2,
    this.ledGrid = true,
    this.gridSize = 8,
  });

  String get shown => text.isEmpty ? ' ' : text;

  Color get color => HSVColor.fromAHSV(
        1,
        hue.clamp(0.0, 360.0).toDouble(),
        saturation.clamp(0.0, 1.0).toDouble(),
        brightness.clamp(0.0, 1.0).toDouble(),
      ).toColor();

  LedSettings copyWith({
    String? text,
    double? hue,
    double? saturation,
    double? brightness,
    double? speed,
    double? fontSize,
    String? font,
    bool? autoSize,
    bool? rainbow,
    bool? leftToRight,
    bool? mirror,
    int? bgColor,
    int? blinkMode,
    double? blinkHz,
    bool? ledGrid,
    double? gridSize,
  }) =>
      LedSettings(
        text: text ?? this.text,
        hue: hue ?? this.hue,
        saturation: saturation ?? this.saturation,
        brightness: brightness ?? this.brightness,
        speed: speed ?? this.speed,
        fontSize: fontSize ?? this.fontSize,
        font: font ?? this.font,
        autoSize: autoSize ?? this.autoSize,
        rainbow: rainbow ?? this.rainbow,
        leftToRight: leftToRight ?? this.leftToRight,
        mirror: mirror ?? this.mirror,
        bgColor: bgColor ?? this.bgColor,
        blinkMode: blinkMode ?? this.blinkMode,
        blinkHz: blinkHz ?? this.blinkHz,
        ledGrid: ledGrid ?? this.ledGrid,
        gridSize: gridSize ?? this.gridSize,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'hue': hue,
        'saturation': saturation,
        'brightness': brightness,
        'speed': speed,
        'fontSize': fontSize,
        'font': font,
        'autoSize': autoSize,
        'rainbow': rainbow,
        'leftToRight': leftToRight,
        'mirror': mirror,
        'bgColor': bgColor,
        'blinkMode': blinkMode,
        'blinkHz': blinkHz,
        'ledGrid': ledGrid,
        'gridSize': gridSize,
      };

  factory LedSettings.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    bool b(String k, bool def) => (j[k] as bool?) ?? def;
    final font = (j['font'] as String?) ?? 'Orbitron';
    return LedSettings(
      text: (j['text'] as String?) ?? 'Hallo Welt 🎉',
      hue: d('hue', 120),
      saturation: d('saturation', 1),
      brightness: d('brightness', 1),
      speed: d('speed', 200),
      fontSize: d('fontSize', 120),
      font: fonts.contains(font) ? font : fonts.first,
      autoSize: b('autoSize', false),
      rainbow: b('rainbow', false),
      leftToRight: b('leftToRight', false),
      mirror: b('mirror', false),
      bgColor: (j['bgColor'] as num?)?.toInt() ?? 0xFF000000,
      blinkMode: (j['blinkMode'] as num?)?.toInt() ?? 0,
      blinkHz: d('blinkHz', 2),
      ledGrid: b('ledGrid', true),
      gridSize: d('gridSize', 8),
    );
  }
}

class Favorite {
  LedSettings s;
  bool inPlaylist;
  Favorite(this.s, {this.inPlaylist = false});

  Map<String, dynamic> toJson() => {'s': s.toJson(), 'inPlaylist': inPlaylist};

  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(
        LedSettings.fromJson(Map<String, dynamic>.from(j['s'] as Map)),
        inPlaylist: (j['inPlaylist'] as bool?) ?? false,
      );
}

class Store {
  static const _kCurrent = 'current';
  static const _kFavs = 'favorites';

  static Future<LedSettings> loadCurrent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kCurrent);
      if (raw == null) return const LedSettings();
      return LedSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const LedSettings();
    }
  }

  static Future<void> saveCurrent(LedSettings s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kCurrent, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static List<Favorite> _seeds() => [
        Favorite(const LedSettings(text: 'Willkommen 👋', hue: 120)),
        Favorite(const LedSettings(
            text: 'Parkplatz belegt 🚫', hue: 0, speed: 0, autoSize: true)),
        Favorite(const LedSettings(
            text: 'Happy Birthday 🎂', rainbow: true, speed: 250)),
      ];

  static Future<List<Favorite>> loadFavs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFavs);
      if (raw == null) return _seeds();
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Favorite.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return _seeds();
    }
  }

  static Future<void> saveFavs(List<Favorite> favs) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kFavs, jsonEncode(favs.map((f) => f.toJson()).toList()));
    } catch (_) {}
  }
}

TextPainter textPainter(String font, double fontSize, String text) =>
    TextPainter(
      text: TextSpan(
          text: text, style: GoogleFonts.getFont(font, fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();

/// Prüft, ob der Text im Querformat aufs Display passt.
String? warningFor(LedSettings s, Size screen) {
  if (s.autoSize && s.speed == 0) return null;
  final t = textPainter(s.font, s.fontSize, s.shown).size;
  if (t.height > screen.shortestSide - 24) {
    return 'Die Schrift ist zu hoch für das Display im Querformat.';
  }
  if (s.speed == 0 && t.width > screen.longestSide - 48) {
    return 'Der Text passt bei dieser Größe nicht komplett aufs Display. '
        'Schrift verkleinern, „Automatisch anpassen" einschalten, Text kürzen '
        'oder Geschwindigkeit über 0 stellen.';
  }
  return null;
}

// ─────────────────────────────── Settings-Seite ───────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _controller = TextEditingController();
  LedSettings _s = const LedSettings();
  List<Favorite> _favs = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Store.loadCurrent();
    final f = await Store.loadFavs();
    if (!mounted) return;
    setState(() {
      _s = s;
      _favs = f;
      _controller.text = s.text;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(LedSettings s) {
    setState(() => _s = s);
    Store.saveCurrent(s);
  }

  String? get _warning => warningFor(_s, MediaQuery.sizeOf(context));

  // ── Favoriten ──
  void _saveFav() {
    final idx = _favs.indexWhere((f) => f.s.text == _s.text);
    setState(() {
      if (idx >= 0) {
        _favs[idx].s = _s;
      } else {
        _favs.add(Favorite(_s));
      }
    });
    Store.saveFavs(_favs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(idx >= 0 ? 'Favorit aktualisiert' : 'Als Favorit gespeichert'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _loadFav(Favorite f) {
    _controller.text = f.s.text;
    _update(f.s);
  }

  void _deleteFav(Favorite f) {
    setState(() => _favs.remove(f));
    Store.saveFavs(_favs);
  }

  // ── Start ──
  Future<void> _launch(List<LedSettings> items, {bool check = true}) async {
    if (Dnd.supported && !await Dnd.hasAccess()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nicht stören'),
          content: const Text(
              'Damit keine Benachrichtigungen das Laufband überdecken, braucht die App '
              'einmalig Zugriff auf „Nicht stören". Jetzt in den Einstellungen erlauben?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Ohne')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Einstellungen')),
          ],
        ),
      );
      if (go == true) {
        await Dnd.openSettings();
        return;
      }
    }
    if (!mounted) return;
    final w = check ? _warning : null;
    if (w != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Achtung'),
          content: Text(w),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Abbrechen')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Trotzdem starten')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MarqueePage(items: items)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _s;
    final stehend = s.speed == 0;
    final playlist = _favs.where((f) => f.inPlaylist).toList();
    final warning = _warning;

    return Scaffold(
      appBar: AppBar(title: const Text('LEDBar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Text ──
          TextField(
            controller: _controller,
            onChanged: (v) => _update(_s.copyWith(text: v)),
            decoration: const InputDecoration(
              labelText: 'Text (Emojis erlaubt)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Vorschau
          Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(s.bgColor),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  s.shown,
                  style: GoogleFonts.getFont(s.font,
                      fontSize: 40,
                      color: s.color,
                      shadows: [Shadow(color: s.color, blurRadius: 12)]),
                ),
              ),
            ),
          ),

          // ── Favoriten & Playlist ──
          _section('Favoriten & Playlist'),
          if (_favs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Noch keine Favoriten.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final f in _favs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: f.inPlaylist,
                onChanged: (v) {
                  setState(() => f.inPlaylist = v ?? false);
                  Store.saveFavs(_favs);
                },
              ),
              title: Text(f.s.text,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  f.s.speed == 0 ? 'stehend' : 'Tempo ${f.s.speed.round()}',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => _loadFav(f),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteFav(f),
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saveFav,
                icon: const Icon(Icons.star_border),
                label: const Text('Aktuelle Einstellung speichern'),
              ),
            ],
          ),
          const Text(
            'Antippen lädt den Favoriten. Haken = kommt in die Playlist '
            '(Reihenfolge wie in der Liste, Tempo-0-Einträge je 5 s).',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),

          // ── Schrift ──
          _section('Schrift'),
          DropdownButtonFormField<String>(
            value: s.font,
            decoration: const InputDecoration(
                labelText: 'Schriftart', border: OutlineInputBorder()),
            items: fonts
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => _update(s.copyWith(font: v ?? s.font)),
          ),
          _slider(
            'Schriftgröße: ${s.fontSize.round()}',
            s.fontSize,
            40,
            300,
            (v) => _update(s.copyWith(fontSize: v)),
            enabled: !(s.autoSize && stehend),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatisch anpassen (bei Tempo 0)'),
            subtitle: const Text('Text füllt das Display genau aus'),
            value: s.autoSize,
            onChanged: (v) => _update(s.copyWith(autoSize: v)),
          ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(warning,
                        style: const TextStyle(color: Colors.orange)),
                  ),
                ],
              ),
            ),

          // ── Farbe ──
          _section('Farbe'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Regenbogen-Modus'),
            subtitle: const Text('Farbton wandert langsam durch'),
            value: s.rainbow,
            onChanged: (v) => _update(s.copyWith(rainbow: v)),
          ),
          _slider(
            'Farbton: ${s.hue.round()}°',
            s.hue,
            0,
            360,
            (v) => _update(s.copyWith(hue: v)),
            activeColor: HSVColor.fromAHSV(1, s.hue, 1, 1).toColor(),
            enabled: !s.rainbow,
          ),
          _slider('Sättigung: ${(s.saturation * 100).round()} %', s.saturation,
              0, 1, (v) => _update(s.copyWith(saturation: v))),
          _slider('Helligkeit: ${(s.brightness * 100).round()} %', s.brightness,
              0.1, 1, (v) => _update(s.copyWith(brightness: v))),
          const SizedBox(height: 8),
          const Text('Hintergrund'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (final c in bgSwatches)
                GestureDetector(
                  onTap: () => _update(s.copyWith(bgColor: c)),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.bgColor == c ? Colors.orange : Colors.white30,
                        width: s.bgColor == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ── Bewegung ──
          _section('Bewegung'),
          _slider(
            'Geschwindigkeit: ${s.speed.round()}'
            '${stehend ? ' (stehend, zentriert)' : ''}',
            s.speed,
            0,
            800,
            (v) => _update(s.copyWith(speed: v)),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.arrow_back),
                  label: Text('Nach links')),
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.arrow_forward),
                  label: Text('Nach rechts')),
            ],
            selected: {s.leftToRight},
            onSelectionChanged: (v) =>
                _update(s.copyWith(leftToRight: v.first)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Spiegeln'),
            subtitle: const Text('z. B. zum Lesen durch eine Scheibe von hinten'),
            value: s.mirror,
            onChanged: (v) => _update(s.copyWith(mirror: v)),
          ),

          // ── Effekte ──
          _section('Effekte'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Aus')),
              ButtonSegment(value: 1, label: Text('Blinken')),
              ButtonSegment(value: 2, label: Text('Pulsieren')),
            ],
            selected: {s.blinkMode},
            onSelectionChanged: (v) => _update(s.copyWith(blinkMode: v.first)),
          ),
          _slider(
            'Frequenz: ${s.blinkHz.toStringAsFixed(1)} Hz',
            s.blinkHz,
            0.5,
            5,
            (v) => _update(s.copyWith(blinkHz: v)),
            enabled: s.blinkMode != 0,
          ),

          // ── LED-Raster ──
          _section('LED-Raster'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Runde LED-Punkte'),
            value: s.ledGrid,
            onChanged: (v) => _update(s.copyWith(ledGrid: v)),
          ),
          _slider(
            'Punktgröße: ${s.gridSize.round()}',
            s.gridSize,
            4,
            20,
            (v) => _update(s.copyWith(gridSize: v.roundToDouble())),
            enabled: s.ledGrid,
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _launch([_s]),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Laufband starten'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
          if (playlist.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () =>
                  _launch(playlist.map((f) => f.s).toList(), check: false),
              icon: const Icon(Icons.playlist_play),
              label: Text('Playlist starten (${playlist.length})'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56)),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent)),
      );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    Color? activeColor,
    bool enabled = true,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: enabled ? null : Colors.white38)),
            Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              activeColor: activeColor,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      );
}

// ───────────────────────────────── Anzeige ────────────────────────────────────

class MarqueePage extends StatefulWidget {
  final List<LedSettings> items;
  const MarqueePage({super.key, required this.items});
  @override
  State<MarqueePage> createState() => _MarqueePageState();
}

class _MarqueePageState extends State<MarqueePage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _t = 0; // Sekunden seit Start (für Blinken / Regenbogen)

  int _i = 0;
  late LedSettings _s;
  late double _speed;
  double _bright = 1.0;
  double _holdLeft = 5; // Haltezeit bei stehenden Playlist-Einträgen

  double? _x;
  TextStyle? _base;
  double _textWidth = 0;
  String? _layoutKey;
  Size _size = Size.zero;

  ui.Image? _tile;
  String? _tileKey;

  bool _overlay = true;
  Timer? _overlayTimer;
  String? _hud;
  Timer? _hudTimer;
  bool _dragLeft = false;

  @override
  void initState() {
    super.initState();
    _s = widget.items.first;
    _speed = _s.speed;

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    Dnd.enable();
    ScreenBrightness().setApplicationScreenBrightness(1.0).catchError((_) {});

    _ticker = createTicker(_onTick)..start();
    _showOverlay();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _overlayTimer?.cancel();
    _hudTimer?.cancel();
    WakelockPlus.disable();
    Dnd.restore();
    ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ── Ablauf ──

  double _startX() => _s.leftToRight ? -_textWidth : _size.width;

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _t += dt;

    if (_x != null && _size != Size.zero) {
      if (_speed > 0) {
        var x = _x! + (_s.leftToRight ? 1 : -1) * _speed * dt;
        final done = _s.leftToRight ? x > _size.width : x < -_textWidth;
        if (done) {
          if (widget.items.length > 1) {
            _next();
            return;
          }
          x = _startX();
        }
        _x = x;
      } else if (widget.items.length > 1) {
        _holdLeft -= dt;
        if (_holdLeft <= 0) {
          _next();
          return;
        }
      }
    }
    setState(() {});
  }

  void _next() {
    _i = (_i + 1) % widget.items.length;
    _s = widget.items[_i];
    _speed = _s.speed;
    _layoutKey = null;
    _x = null;
    _holdLeft = 5;
    setState(() {});
  }

  void _ensureLayout(Size size) {
    final key = '${size.width}x${size.height}-$_i-${_speed == 0}';
    if (_layoutKey == key) return;
    _layoutKey = key;
    _size = size;

    var fs = _s.fontSize;
    if (_s.autoSize && _speed == 0) {
      final tp = textPainter(_s.font, 100, _s.shown);
      fs = math.min((size.width - 48) / tp.width,
              (size.height - 16) / tp.height) *
          100;
    }
    _base = GoogleFonts.getFont(_s.font, fontSize: fs);
    _textWidth = textPainter(_s.font, fs, _s.shown).width;
    _x = _startX();
  }

  // ── LED-Raster (gekachelte Textur mit runden Löchern) ──

  void _ensureTile(double dpr) {
    if (!_s.ledGrid) return;
    final key = '${_s.gridSize}-${_s.bgColor}-$dpr';
    if (_tileKey == key) return;
    _tileKey = key;
    _buildTile(key, _s.gridSize, Color(_s.bgColor), dpr);
  }

  Future<void> _buildTile(
      String key, double step, Color bg, double dpr) async {
    final px = math.max(2, (step * dpr).round());
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble());
    c.saveLayer(r, Paint());
    c.drawRect(r, Paint()..color = bg);
    c.drawCircle(r.center, px * 0.42, Paint()..blendMode = BlendMode.clear);
    c.restore();
    final img = await rec.endRecording().toImage(px, px);
    if (!mounted || _tileKey != key) {
      img.dispose();
      return;
    }
    setState(() => _tile = img);
  }

  // ── Effekte ──

  Color _textColor() {
    if (_s.rainbow) {
      return HSVColor.fromAHSV(
        1,
        (_t * 60) % 360,
        _s.saturation.clamp(0.0, 1.0).toDouble(),
        _s.brightness.clamp(0.0, 1.0).toDouble(),
      ).toColor();
    }
    return _s.color;
  }

  double _opacity() {
    switch (_s.blinkMode) {
      case 1:
        return ((_t * _s.blinkHz) % 1) < 0.5 ? 1.0 : 0.0;
      case 2:
        return 0.2 + 0.8 * (0.5 + 0.5 * math.sin(2 * math.pi * _s.blinkHz * _t));
      default:
        return 1.0;
    }
  }

  // ── Bedienung ──

  void _showOverlay() {
    _overlay = true;
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  void _toggleOverlay() {
    if (_overlay) {
      _overlayTimer?.cancel();
      setState(() => _overlay = false);
    } else {
      setState(_showOverlay);
    }
  }

  void _flashHud(String text) {
    _hud = text;
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  void _onDrag(double dy, Size size) {
    if (_dragLeft) {
      _bright = (_bright - dy / (size.height * 0.8)).clamp(0.05, 1.0).toDouble();
      ScreenBrightness()
          .setApplicationScreenBrightness(_bright)
          .catchError((_) {});
      _flashHud('Helligkeit ${(_bright * 100).round()} %');
    } else {
      _speed = (_speed - dy * 3).clamp(0.0, 1000.0).toDouble();
      _flashHud('Tempo ${_speed.round()}');
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Scaffold(
      backgroundColor: Color(_s.bgColor),
      body: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        _ensureLayout(size);
        _x ??= _startX();
        _ensureTile(dpr);

        final color = _textColor();
        final style = _base!.copyWith(
          color: color,
          shadows: [
            Shadow(color: color, blurRadius: 20),
            Shadow(color: color, blurRadius: 40),
          ],
        );
        final text = Text(_s.shown, style: style, softWrap: false);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          onVerticalDragStart: (d) =>
              _dragLeft = d.localPosition.dx < size.width / 2,
          onVerticalDragUpdate: (d) => _onDrag(d.delta.dy, size),
          child: Stack(
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(_s.mirror ? -1 : 1, 1, 1),
                child: Stack(
                  children: [
                    Opacity(
                      opacity: _opacity(),
                      child: ClipRect(
                        child: _speed == 0
                            ? Center(child: text)
                            : OverflowBox(
                                alignment: Alignment.centerLeft,
                                maxWidth: double.infinity,
                                child: Transform.translate(
                                  offset: Offset(_x!, 0),
                                  child: text,
                                ),
                              ),
                      ),
                    ),
                    if (_s.ledGrid && _tile != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _DotPainter(
                                  _tile!, _s.gridSize / _tile!.width),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_overlay)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton.filled(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Wischen links: Helligkeit · Wischen rechts: Tempo · Tippen: Menü ein/aus',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_hud != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_hud!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// Legt eine gekachelte Textur mit runden Löchern über die Anzeige:
/// der Text scheint nur durch die "LED-Punkte".
class _DotPainter extends CustomPainter {
  final ui.Image tile;
  final double scale;
  _DotPainter(this.tile, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ImageShader(
        tile,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.diagonal3Values(scale, scale, 1).storage,
        filterQuality: FilterQuality.low,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) =>
      old.tile != tile || old.scale != scale;
}
