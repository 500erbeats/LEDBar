import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:io' show Platform;

void main() => runApp(const LedApp());

class Dnd {
  static const _ch = MethodChannel('led_laufbar/dnd');
  // Android-Werte: 1 = alles erlaubt, 2 = nur Prioritäts-Unterbrechungen, 3 = keine, 4 = nur Wecker
  static int? _previous;

  static bool get supported => Platform.isAndroid;

  static Future<bool> hasAccess() async =>
      supported && (await _ch.invokeMethod<bool>('hasAccess') ?? false);

  static Future<void> openSettings() => _ch.invokeMethod('openSettings');

  /// Schaltet DND an. Gibt false zurück, wenn die Berechtigung fehlt.
  static Future<bool> enable() async {
    if (!await hasAccess()) return false;
    _previous = await _ch.invokeMethod<int>('getFilter');
    return await _ch.invokeMethod<bool>('setFilter', 3) ?? false; // 3 = komplett still
  }

  static Future<void> restore() async {
    if (_previous == null || !await hasAccess()) return;
    await _ch.invokeMethod('setFilter', _previous);
    _previous = null;
  }
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

class LedSettings {
  final String text;
  final double hue; // 0-360
  final double brightness; // 0.1-1
  final double speed; // px/s
  final double fontSize;
  final String font;
  final bool ledGrid;
  const LedSettings({
    required this.text,
    required this.hue,
    required this.brightness,
    required this.speed,
    required this.fontSize,
    required this.font,
    required this.ledGrid,
  });

  Color get color => HSVColor.fromAHSV(1, hue, 1, brightness).toColor();
}

const fonts = [
  'Orbitron',
  'Press Start 2P',
  'VT323',
  'Audiowide',
  'Bebas Neue',
  'Roboto Mono',
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _controller = TextEditingController(text: 'Hallo Welt 🎉');
  double _hue = 120;
  double _brightness = 1;
  double _speed = 200;
  double _fontSize = 120;
  String _font = fonts.first;
  bool _grid = true;

  LedSettings get _settings => LedSettings(
        text: _controller.text.isEmpty ? ' ' : _controller.text,
        hue: _hue,
        brightness: _brightness,
        speed: _speed,
        fontSize: _fontSize,
        font: _font,
        ledGrid: _grid,
      );

  Future<void> _start() async {
    if (Dnd.supported && !await Dnd.hasAccess()) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nicht stören'),
          content: const Text(
              'Damit keine Benachrichtigungen das Laufband überdecken, braucht die App '
              'einmalig Zugriff auf „Nicht stören". Jetzt in den Einstellungen erlauben?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ohne')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Einstellungen')),
          ],
        ),
      );
      if (go == true) {
        await Dnd.openSettings();
        return; // nach dem Erlauben einfach nochmal auf Start tippen
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MarqueePage(settings: _settings)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('LEDBar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Text (Emojis erlaubt)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Vorschau
          Container(
            height: 80,
            alignment: Alignment.center,
            color: Colors.black,
            child: FittedBox(
              child: Text(
                s.text,
                style: GoogleFonts.getFont(s.font,
                    fontSize: 40,
                    color: s.color,
                    shadows: [Shadow(color: s.color, blurRadius: 12)]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _font,
            decoration: const InputDecoration(
                labelText: 'Schriftart', border: OutlineInputBorder()),
            items: fonts
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _font = v!),
          ),
          _slider('Farbton', _hue, 0, 360, (v) => _hue = v,
              activeColor: HSVColor.fromAHSV(1, _hue, 1, 1).toColor()),
          _slider('Helligkeit', _brightness, 0.1, 1, (v) => _brightness = v),
          _slider('Geschwindigkeit', _speed, 50, 800, (v) => _speed = v),
          _slider('Schriftgröße', _fontSize, 40, 300, (v) => _fontSize = v),
          SwitchListTile(
            title: const Text('LED-Raster'),
            value: _grid,
            onChanged: (v) => setState(() => _grid = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Laufband starten'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      void Function(double) onChanged,
      {Color? activeColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${value.round()}'
              '${label == 'Helligkeit' ? '' : ''}'),
          Slider(
            value: value,
            min: min,
            max: max,
            activeColor: activeColor,
            onChanged: (v) => setState(() => onChanged(v)),
          ),
        ],
      ),
    );
  }
}

class MarqueePage extends StatefulWidget {
  final LedSettings settings;
  const MarqueePage({super.key, required this.settings});
  @override
  State<MarqueePage> createState() => _MarqueePageState();
}

class _MarqueePageState extends State<MarqueePage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final TextStyle _style;
  late final double _textWidth;
  Duration _last = Duration.zero;
  double? _x;
  double _screenWidth = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    Dnd.enable();

    _style = GoogleFonts.getFont(
      s.font,
      fontSize: s.fontSize,
      color: s.color,
      shadows: [
        Shadow(color: s.color, blurRadius: 20),
        Shadow(color: s.color, blurRadius: 40),
      ],
    );
    final tp = TextPainter(
      text: TextSpan(text: s.text, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    _textWidth = tp.width;

    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      if (_x == null || _screenWidth == 0) return;
      var x = _x! - s.speed * dt;
      if (x < -_textWidth) x = _screenWidth;
      setState(() => _x = x);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    WakelockPlus.disable();
    Dnd.restore();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: LayoutBuilder(builder: (context, c) {
          _screenWidth = c.maxWidth;
          _x ??= c.maxWidth;
          return Stack(
            children: [
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(_x!, 0),
                    child: Text(s.text, style: _style, softWrap: false),
                  ),
                ),
              ),
              if (s.ledGrid)
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// Schwarzes Raster über dem Text -> LED-Punkt-Optik
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 8.0;
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}