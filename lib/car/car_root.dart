import 'package:flutter/material.dart';

/// Raíz del modo tableta. (Stub — lo implementa el agente de UI de tableta.)
class CarRoot extends StatelessWidget {
  const CarRoot({super.key, this.demo = false, required this.onChangeMode});
  final bool demo;
  final VoidCallback onChangeMode;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Car mode')));
}
