import 'package:flutter/material.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/phone_widgets.dart';

/// Raíz del modo celular (transmisor). Material Design 3 + Material You.
class PhoneRoot extends StatefulWidget {
  const PhoneRoot({super.key, required this.onChangeMode});
  final VoidCallback onChangeMode;

  @override
  State<PhoneRoot> createState() => _PhoneRootState();
}

class _PhoneRootState extends State<PhoneRoot> {
  final _c = PhoneController();

  @override
  void initState() {
    super.initState();
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final needsSetup = !_c.permissionsOk || !_c.runtimeOk;
        final permissions = [
          const SectionHeader('Permisos'),
          PermissionsCard(c: _c),
        ];
        final children = <Widget>[
          TransmitCard(
            running: _c.status.running,
            busy: _c.busy,
            enabled: _c.permissionsOk,
            cars: _c.status.clients.length,
            port: _c.status.port,
            onTap: _c.toggle,
          ),
          const SizedBox(height: 12),
          AutoStartCard(value: _c.autoStart, onChanged: _c.setAutoStart),
          if (needsSetup) ...permissions,
          const SectionHeader('Leer música de'),
          SourceSelector(value: _c.source, onChanged: _c.setSource),
          const SectionHeader('Sonando ahora'),
          NowPlayingCard(
            session: _c.status.session,
            lyricsStatus: _c.status.lyricsStatus,
            running: _c.status.running,
          ),
          const SectionHeader('Pantallas conectadas'),
          CarsCard(cars: _c.status.clients, running: _c.status.running),
          const SectionHeader('Cómo conectar'),
          HelpCard(ips: _c.localIps, port: _c.status.port),
          if (!needsSetup) ...permissions,
        ];
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text('Pixel Car Player'),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Más opciones',
                    onSelected: (v) {
                      if (v == 'mode') widget.onChangeMode();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'mode',
                        child: ListTile(
                          leading: Icon(Icons.swap_horiz_rounded),
                          title: Text('Cambiar modo'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverSafeArea(
                top: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
