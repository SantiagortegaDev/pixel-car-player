import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
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
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.link.status]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        children: [
          const Text(
            'Ajustes',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: HarmonixColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.demo ? 'Modo demo activo — datos simulados' : _statusText(c.displayStatus),
            style: const TextStyle(fontSize: 18, color: HarmonixColors.textSecondary),
          ),
          _Section('Conexión con el celular'),
          _Choice(
            icon: Icons.wifi_rounded,
            title: 'Wi-Fi automático',
            subtitle: 'Hotspot del celular o la misma red. Se busca solo.',
            selected: c.prefs.btAddress == null,
            onTap: () => _pickBt(null, null),
          ),
          if (_loadingBonded)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bonded.isEmpty)
            const _Hint(
              'No hay celulares emparejados por Bluetooth (o este radio no expone el Bluetooth estándar). '
              'Usa Wi-Fi.',
            )
          else
            for (final d in _bonded)
              _Choice(
                icon: Icons.bluetooth_rounded,
                title: (d['name'] as String?)?.isNotEmpty == true
                    ? d['name'] as String
                    : 'Dispositivo',
                subtitle: 'Bluetooth · ${d['address']}',
                selected: c.prefs.btAddress == d['address'],
                onTap: () => _pickBt(d['address'] as String?, d['name'] as String?),
              ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ip,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 22),
                  decoration: InputDecoration(
                    labelText: 'IP manual del celular (opcional)',
                    hintText: '192.168.43.1',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                  child: const Text('Guardar', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.lan_rounded,
            label: 'IP de esta tableta',
            value: c.tabletIps.isEmpty ? 'sin red' : c.tabletIps.join('  ·  '),
          ),
          _Section('Pantalla'),
          _SwitchRow(
            icon: Icons.light_mode_rounded,
            title: 'Mantener pantalla encendida',
            value: c.prefs.keepScreenOn,
            onChanged: c.setKeepScreenOn,
          ),
          _SwitchRow(
            icon: Icons.play_circle_outline_rounded,
            title: 'Modo demo',
            subtitle: 'Canciones de ejemplo para probar la pantalla sin celular.',
            value: c.demo,
            onChanged: c.setDemo,
          ),
          _Section('Aplicación'),
          SizedBox(
            height: 64,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onChangeMode();
              },
              icon: const Icon(Icons.swap_horiz_rounded, size: 28),
              label: const Text('Cambiar modo (celular/tableta)', style: TextStyle(fontSize: 19)),
            ),
          ),
        ],
      ),
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
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: HarmonixColors.accentBright,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(text, style: const TextStyle(color: HarmonixColors.textSecondary, fontSize: 16)),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected
          ? HarmonixColors.accent.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? HarmonixColors.accent : Colors.white.withValues(alpha: 0.06),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: selected ? HarmonixColors.accentBright : HarmonixColors.textSecondary,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: HarmonixColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 15, color: HarmonixColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 30,
                  color: selected ? HarmonixColors.accentBright : HarmonixColors.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
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
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => onChanged(!value),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 30, color: HarmonixColors.textSecondary),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: HarmonixColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 15, color: HarmonixColors.textSecondary),
                    ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.3,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
    child: Row(
      children: [
        Icon(icon, size: 26, color: HarmonixColors.textSecondary),
        const SizedBox(width: 18),
        Text('$label: ', style: const TextStyle(fontSize: 17, color: HarmonixColors.textSecondary)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: HarmonixColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}
