import 'package:flutter/widgets.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';

/// Hace llegar la [CarCustomization] actual a los widgets de la pantalla del carro
/// (textos, visibilidad…). Sin scope se usan los valores por defecto.
class CarCustomScope extends InheritedWidget {
  const CarCustomScope({super.key, required this.value, required super.child});

  final CarCustomization value;

  static CarCustomization of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CarCustomScope>()?.value ?? CarCustomization.defaults;

  @override
  bool updateShouldNotify(CarCustomScope oldWidget) => !identical(value, oldWidget.value);
}
