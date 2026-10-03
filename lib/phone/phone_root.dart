import 'package:flutter/material.dart';

/// Raíz del modo celular. (Stub — lo implementa el agente de UI de celular.)
class PhoneRoot extends StatelessWidget {
  const PhoneRoot({super.key, required this.onChangeMode});
  final VoidCallback onChangeMode;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Phone mode')));
}
