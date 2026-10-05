import 'dart:convert';

import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';

/// Copia de seguridad completa de la tableta: personalización + celulares de confianza +
/// preferencias del enlace. Se exporta antes de instalar una actualización y se puede
/// guardar a un archivo o al portapapeles.
class CarBackup {
  const CarBackup({
    required this.customization,
    this.trustedPhones = const {},
    this.requirePairing = true,
    this.link = const {},
    this.exportedAt,
  });

  static const kind = 'pixel-car-player/car-backup';
  static const version = 1;

  final CarCustomization customization;

  /// `{id: {token, name, pairedAt}}` (como `car_trusted_phones`).
  final Map<String, dynamic> trustedPhones;
  final bool requirePairing;

  /// `{manualIp, btAddress, btName, keepScreenOn}`.
  final Map<String, dynamic> link;
  final DateTime? exportedAt;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'v': version,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'customization': customization.toJson(),
    'trustedPhones': trustedPhones,
    'requirePairing': requirePairing,
    'link': link,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Lee una copia completa o solo la personalización (formato viejo de "Exportar").
  /// Lanza [FormatException] si no es un objeto JSON.
  static CarBackup decode(String text) {
    final Object? raw = jsonDecode(text.trim());
    if (raw is! Map) throw const FormatException('Se esperaba un objeto JSON');
    final m = Map<String, dynamic>.from(raw);
    final shapes = CarCustomizationStore.shapeNames;
    if (m['kind'] != kind && !m.containsKey('customization')) {
      return CarBackup(customization: CarCustomization.fromJson(m, shapes: shapes));
    }
    final phones = m['trustedPhones'];
    final link = m['link'];
    return CarBackup(
      customization: CarCustomization.fromJson(m['customization'], shapes: shapes),
      trustedPhones: phones is Map ? Map<String, dynamic>.from(phones) : const {},
      requirePairing: m['requirePairing'] is bool ? m['requirePairing'] as bool : true,
      link: link is Map ? Map<String, dynamic>.from(link) : const {},
      exportedAt: DateTime.tryParse('${m['exportedAt']}'),
    );
  }

  /// `true` si la copia trae más que la personalización.
  bool get isFull => trustedPhones.isNotEmpty || link.isNotEmpty;

  /// Nombre de archivo con fecha (`pixel-car-player-config-2026-10-04.json`).
  static String fileName([DateTime? at]) {
    final d = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'pixel-car-player-config-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }
}
