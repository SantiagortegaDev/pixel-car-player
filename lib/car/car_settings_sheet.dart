import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Abre los ajustes de la tableta.
Future<void> showCarSettings(
  BuildContext context, {
  required CarController controller,
  required VoidCallback onChangeMode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 820),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: CarSettingsSheet(controller: controller, onChangeMode: onChangeMode),
    ),
  );
}

class CarSettingsSheet extends StatefulWidget {
  const CarSettingsSheet({super.key, required this.controller, required this.onChangeMode});
  final CarController controller;
  final VoidCallback onChangeMode;

  @override
  State<CarSettingsSheet> createState() => _CarSettingsSheetState();
}

class _CarSettingsSheetState extends State<CarSettingsSheet> {
  late final TextEditingController _ip = TextEditingController(
    text: widget.controller.prefs.manualIp ?? '',
  );
  List<Map<String, dynamic>> _bonded = const [];

  /// Pestaña elegida en el SegmentedButton (null = según la conexión guardada).
  bool? _bluetooth;
  bool _loadingBonded = true;

  CarController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadBonded();
  }

  Future<void> _loadBonded() async {
    await NativeBridge.instance.requestRuntimePermissions();
    final list = await NativeBridge.instance.getBondedDevices();
    if (!mounted) return;
    setState(() {
      _bonded = list;
      _loadingBonded = false;
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _saveIp() async {
    FocusScope.of(context).unfocus();
    await c.setConnection(
      manualIp: _ip.text.trim(),
      btAddress: c.prefs.btAddress,
      btName: c.prefs.btName,
    );
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('IP guardada. Reconectando…')));
    }
  }

  Future<void> _pickBt(String? address, String? name) async {
    await c.setConnection(manualIp: c.prefs.manualIp, btAddress: address, btName: name);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.link.status]),
      builder: (context, _) {
        final bt = _bluetooth ?? c.prefs.btAddress != null;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('Ajustes', style: tt.headlineMedium?.copyWith(color: cs.onSurface)),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                c.demo ? 'Modo demo activo — datos simulados' : _statusText(c.displayStatus),
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontSize: 18),
              ),
            ),
            const _Section('Conexión con el celular'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.wifi_rounded),
                  label: Text('Wi-Fi'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.bluetooth_rounded),
                  label: Text('Bluetooth'),
                ),
              ],
              selected: {bt},
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, 48),
                visualDensity: const VisualDensity(vertical: 4),
                textStyle: tt.titleMedium?.copyWith(fontSize: 18),
                iconSize: 24,
              ),
              onSelectionChanged: (v) {
                final wantBt = v.first;
                setState(() => _bluetooth = wantBt);
                if (!wantBt) _pickBt(null, null);
              },
            ),
            const SizedBox(height: 16),
            if (!bt) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Hotspot del celular o la misma red Wi-Fi. Se busca solo; la IP manual es opcional.',
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ip,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: tt.titleLarge,
                      decoration: InputDecoration(
                        labelText: 'IP manual del celular (opcional)',
                        hintText: '192.168.43.1',
                        prefixIcon: const Icon(Icons.router_outlined),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      ),
                      onSubmitted: (_) => _saveIp(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 64,
                    child: FilledButton(
                      onPressed: _saveIp,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        textStyle: tt.titleMedium?.copyWith(fontSize: 18),
                      ),
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ] else if (_loadingBonded)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_bonded.isEmpty)
              Card(
                color: cs.surfaceContainerHigh,
                child: ListTile(
                  minVerticalPadding: 16,
                  leading: Icon(Icons.bluetooth_disabled_rounded, color: cs.onSurfaceVariant),
                  title: const Text(
                    'No hay celulares emparejados por Bluetooth (o este radio no expone el '
                    'Bluetooth estándar). Usa Wi-Fi.',
                  ),
                ),
              )
            else
              Card(
                color: cs.surfaceContainer,
                child: Column(
                  children: [
                    for (final d in _bonded)
                      _DeviceTile(
                        title: (d['name'] as String?)?.isNotEmpty == true
                            ? d['name'] as String
                            : 'Dispositivo',
                        subtitle: '${d['address']}',
                        selected: c.prefs.btAddress == d['address'],
                        onTap: () => _pickBt(d['address'] as String?, d['name'] as String?),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            ListTile(
              minTileHeight: 64,
              leading: Icon(Icons.lan_outlined, color: cs.onSurfaceVariant),
              title: const Text('IP de esta tableta'),
              titleTextStyle: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontSize: 18),
              trailing: Text(
                c.tabletIps.isEmpty ? 'sin red' : c.tabletIps.join('  ·  '),
                style: tt.titleMedium?.copyWith(color: cs.onSurface, fontSize: 19),
              ),
            ),
            const _Section('Pantalla'),
            Card(
              color: cs.surfaceContainer,
              child: Column(
                children: [
                  _Switch(
                    icon: Icons.light_mode_outlined,
                    title: 'Mantener pantalla encendida',
                    value: c.prefs.keepScreenOn,
                    onChanged: c.setKeepScreenOn,
                  ),
                  Divider(height: 1, indent: 64, endIndent: 20, color: cs.outlineVariant),
                  _Switch(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'Modo demo',
                    subtitle: 'Canciones de ejemplo para probar la pantalla sin celular.',
                    value: c.demo,
                    onChanged: c.setDemo,
                  ),
                ],
              ),
            ),
            const _Section('Aplicación'),
            SizedBox(
              height: 64,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onChangeMode();
                },
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  textStyle: tt.titleMedium?.copyWith(fontSize: 18),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 26),
                label: const Text('Cambiar modo (celular/tableta)'),
              ),
            ),
          ],
        );
      },
    );
  }

  String _statusText(LinkStatus st) => switch (st.phase) {
    LinkPhase.connected =>
      'Conectado a ${st.device} por ${st.transport == 'bt' ? 'Bluetooth' : 'Wi-Fi'} (${st.address})',
    LinkPhase.searching => 'Buscando al celular…',
    LinkPhase.disconnected => 'Sin conexión',
  };
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 28, 8, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 17,
      ),
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 76,
      onTap: onTap,
      selected: selected,
      selectedTileColor: cs.secondaryContainer,
      selectedColor: cs.onSecondaryContainer,
      leading: const Icon(Icons.smartphone_rounded, size: 28),
      title: Text(title, style: const TextStyle(fontSize: 19)),
      subtitle: Text('Bluetooth · $subtitle', style: const TextStyle(fontSize: 15)),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        size: 28,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    minTileHeight: 76,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    secondary: Icon(icon, size: 28),
    title: Text(title, style: const TextStyle(fontSize: 19)),
    subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 15)),
    value: value,
    onChanged: onChanged,
  );
}
