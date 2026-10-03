import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Formas de Material 3 Expressive (androidx.graphics.shapes / M3Shapes), portadas de
/// Harmonix v2 `web/src/lib/shapes.js`.
///
/// Cada forma se remuestrea en coordenadas polares con [n] puntos: sirve para recortar
/// (Path), para interpolar entre formas (morphing, mismo número de vértices) y
/// [M3Shape.radiusAt] da la distancia al borde (barras del visualizador).
class M3Shape {
  const M3Shape._(this.radii);

  /// Radio normalizado (0..1) en [n] ángulos equiespaciados; k=0 es arriba, horario.
  final Float32List radii;

  static const int n = 120;
  static const double _tau = math.pi * 2;

  /// Distancia normalizada al borde en [angle] radianes (0 = arriba, horario).
  double radiusAt(double angle) {
    final f = (((angle / _tau) % 1) + 1) % 1 * n;
    final i = f.floor();
    final t = f - i;
    return radii[i % n] * (1 - t) + radii[(i + 1) % n] * t;
  }

  /// Contorno dentro de [rect] (centrado), rotado [rotation] radianes.
  Path toPath(Rect rect, {double rotation = 0}) {
    final c = rect.center;
    final rx = rect.width / 2, ry = rect.height / 2;
    final p = Path();
    for (var k = 0; k < n; k++) {
      final t = k / n * _tau - math.pi / 2 + rotation;
      final r = radii[k];
      final x = c.dx + rx * r * math.cos(t);
      final y = c.dy + ry * r * math.sin(t);
      k == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  /// Interpolación entre formas (morphing).
  static M3Shape lerp(M3Shape a, M3Shape b, double t) {
    final out = Float32List(n);
    for (var k = 0; k < n; k++) {
      out[k] = a.radii[k] + (b.radii[k] - a.radii[k]) * t;
    }
    return M3Shape._(out);
  }

  // ---- Catálogo (mismos parámetros que shapes.js) ----
  static final circle = M3Shape._(Float32List(n)..fillRange(0, n, 1));
  static final cookie4 = _star(4, 0.7, 0.55, offset: math.pi / 4);
  static final cookie6 = _star(6, 0.75, 0.5);
  static final cookie7 = _star(7, 0.75, 0.5);
  static final cookie9 = _star(9, 0.8, 0.5);
  static final cookie12 = _star(12, 0.8, 0.5);
  static final sunny = _star(8, 0.8, 0.15);
  static final verySunny = _star(8, 0.7, 0.15);
  static final softBurst = _star(10, 0.72, 0.25);
  static final clover4 = _star(4, 0.38, 1, offset: math.pi / 4, innerRounding: 0.04);
  static final clover8 = _star(8, 0.62, 1, innerRounding: 0.04);
  static final pentagon = _regular(5, 0.28);
  static final triangle = _regular(3, 0.3);
  static final gem = _regular(6, 0.2, rot: 0);
  static final square = _rect(1, 1, 0.3);
  static final pill = _rect(1, 0.55, 0.55);
  static final oval = _ellipse(1, 0.68);

  static final Map<String, M3Shape> all = {
    'circle': circle,
    'cookie4': cookie4,
    'cookie6': cookie6,
    'cookie7': cookie7,
    'cookie9': cookie9,
    'cookie12': cookie12,
    'sunny': sunny,
    'verySunny': verySunny,
    'softBurst': softBurst,
    'clover4': clover4,
    'clover8': clover8,
    'pentagon': pentagon,
    'triangle': triangle,
    'gem': gem,
    'square': square,
    'pill': pill,
    'oval': oval,
  };

  /// Secuencia del indicador de carga de MD3 Expressive.
  static final loadingSequence = [softBurst, cookie9, pentagon, pill, sunny, cookie4, oval];

  // ---- Construcción ----
  static M3Shape _star(int points, double inner, double rounding,
          {double offset = 0, double? innerRounding}) =>
      _polar(_roundedOutline(
        List.generate(points * 2, (i) {
          final a = i * math.pi / points - math.pi / 2 + offset;
          final r = i.isOdd ? inner : 1.0;
          return Offset(r * math.cos(a), r * math.sin(a));
        }),
        rounding,
        innerRounding ?? rounding,
      ));

  static M3Shape _regular(int sides, double rounding, {double rot = -math.pi / 2}) =>
      _polar(_roundedOutline(
        List.generate(sides, (i) {
          final a = i * _tau / sides + rot;
          return Offset(math.cos(a), math.sin(a));
        }),
        rounding,
        rounding,
      ));

  static M3Shape _rect(double w, double h, double rounding) => _polar(
      _roundedOutline([Offset(-w, -h), Offset(w, -h), Offset(w, h), Offset(-w, h)],
          rounding, rounding));

  static M3Shape _ellipse(double w, double h) {
    final out = Float32List(n);
    var mx = 0.0;
    for (var k = 0; k < n; k++) {
      final t = k / n * _tau - math.pi / 2;
      out[k] = 1 / math.sqrt(math.pow(math.cos(t) / w, 2) + math.pow(math.sin(t) / h, 2));
      mx = math.max(mx, out[k]);
    }
    for (var k = 0; k < n; k++) {
      out[k] /= mx;
    }
    return M3Shape._(out);
  }

  /// Contorno denso de un polígono con esquinas redondeadas (arcos tangentes).
  static List<Offset> _roundedOutline(
      List<Offset> v, double rounding, double innerRounding) {
    final n = v.length;
    Offset at(int i) => v[(i % n + n) % n];
    Offset norm(Offset a) => a.distance == 0 ? a : a / a.distance;
    final geo = List.generate(n, (i) {
      final u1 = norm(at(i - 1) - v[i]);
      final u2 = norm(at(i + 1) - v[i]);
      final dot = (u1.dx * u2.dx + u1.dy * u2.dy).clamp(-1.0, 1.0);
      final angle = math.acos(dot);
      final tanHalf = math.tan(angle / 2);
      return (u1: u1, u2: u2, angle: angle, tanHalf: tanHalf,
          want: (i.isOdd ? innerRounding : rounding) / tanHalf);
    });
    double cutOn(int i, int side) {
      final j = side < 0 ? i - 1 : i + 1;
      final a = geo[(i % n + n) % n].want;
      final b = geo[(j % n + n) % n].want;
      final edge = (at(j) - at(i)).distance;
      return a + b > edge ? edge * a / (a + b) : a;
    }

    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final g = geo[i];
      final cut = math.min(cutOn(i, -1), cutOn(i, 1));
      final r = cut * g.tanHalf;
      if (r < 1e-4) {
        out.add(v[i]);
        continue;
      }
      final p1 = v[i] + g.u1 * cut;
      final p2 = v[i] + g.u2 * cut;
      final center = v[i] + norm(g.u1 + g.u2) * (r / math.sin(g.angle / 2));
      final a1 = math.atan2(p1.dy - center.dy, p1.dx - center.dx);
      final a2 = math.atan2(p2.dy - center.dy, p2.dx - center.dx);
      var d = a2 - a1;
      while (d > math.pi) {
        d -= _tau;
      }
      while (d < -math.pi) {
        d += _tau;
      }
      const steps = 16;
      for (var k = 0; k <= steps; k++) {
        final a = a1 + d * k / steps;
        out.add(Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a)));
      }
    }
    return out;
  }

  /// Radio del contorno visto desde el centro en [n] ángulos equiespaciados.
  static M3Shape _polar(List<Offset> outline) {
    final radii = Float32List(n);
    var mx = 0.0;
    for (var k = 0; k < n; k++) {
      final t = k / n * _tau - math.pi / 2;
      final dx = math.cos(t), dy = math.sin(t);
      var best = 0.0;
      for (var i = 0; i < outline.length; i++) {
        final a = outline[i];
        final b = outline[(i + 1) % outline.length];
        final ex = b.dx - a.dx, ey = b.dy - a.dy;
        final den = dx * ey - dy * ex;
        if (den.abs() < 1e-9) continue;
        final s = (a.dx * ey - a.dy * ex) / den;
        final u = (a.dx * dy - a.dy * dx) / den;
        if (s > 0 && u >= -1e-6 && u <= 1 + 1e-6) best = math.max(best, s);
      }
      radii[k] = best;
      mx = math.max(mx, best);
    }
    for (var k = 0; k < n; k++) {
      radii[k] /= mx;
    }
    return M3Shape._(radii);
  }
}

/// Recorta [child] con una [M3Shape] (opcionalmente rotada).
class M3ShapeClipper extends CustomClipper<Path> {
  const M3ShapeClipper(this.shape, {this.rotation = 0});
  final M3Shape shape;
  final double rotation;

  @override
  Path getClip(Size size) => shape.toPath(Offset.zero & size, rotation: rotation);

  @override
  bool shouldReclip(M3ShapeClipper old) =>
      old.shape != shape || old.rotation != rotation;
}

/// Borde de forma M3 para `Material`/`Container` (decoración, tinta, sombras).
class M3ShapeBorder extends OutlinedBorder {
  const M3ShapeBorder(this.shape, {this.rotation = 0, super.side});
  final M3Shape shape;
  final double rotation;

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      M3ShapeBorder(shape, rotation: rotation, side: side ?? this.side);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      shape.toPath(rect.deflate(side.width), rotation: rotation);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      shape.toPath(rect, rotation: rotation);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      M3ShapeBorder(shape, rotation: rotation, side: side.scale(t));
}
