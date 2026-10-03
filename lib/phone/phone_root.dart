import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/theme/colors.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/phone_widgets.dart';

/// Raíz del modo celular (transmisor).
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
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final needsSetup = !_c.permissionsOk || !_c.runtimeOk;
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0E2655),
                  HarmonixColors.background,
                  HarmonixColors.backgroundDark,
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [
                                    HarmonixColors.accentBright,
                                    HarmonixColors.accentDim,
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.directions_car_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Pixel Car Player', style: t.titleLarge),
                                  Text('Modo transmisor', style: t.bodySmall),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              color: HarmonixColors.surfaceVariant,
                              onSelected: (v) {
                                if (v == 'mode') widget.onChangeMode();
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'mode',
                                  child: Text('Cambiar modo'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TransmitToggle(
                          running: _c.status.running,
                          busy: _c.busy,
                          enabled: _c.permissionsOk,
                          cars: _c.status.clients.length,
                          onTap: _c.toggle,
                        ),
                        const SizedBox(height: 10),
                        PCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Iniciar automáticamente',
                                      style: t.titleSmall,
                                    ),
                                    Text(
                                      'Al abrir la app, si están los permisos',
                                      style: t.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _c.autoStart,
                                onChanged: _c.setAutoStart,
                              ),
                            ],
                          ),
                        ),
                        if (needsSetup) ...[
                          const SizedBox(height: 14),
                          const SectionTitle(
                            'Permisos',
                            icon: Icons.verified_user_outlined,
                          ),
                          PermissionsCard(c: _c),
                        ],
                        const SizedBox(height: 14),
                        const SectionTitle(
                          'Leer música de',
                          icon: Icons.library_music_outlined,
                        ),
                        SourceSelector(
                          value: _c.source,
                          onChanged: _c.setSource,
                        ),
                        const SizedBox(height: 14),
                        const SectionTitle(
                          'Sonando ahora',
                          icon: Icons.music_note_rounded,
                        ),
                        NowPlayingCard(
                          session: _c.status.session,
                          lyricsStatus: _c.status.lyricsStatus,
                          running: _c.status.running,
                        ),
                        const SizedBox(height: 14),
                        const SectionTitle(
                          'Pantallas conectadas',
                          icon: Icons.tablet_android_rounded,
                        ),
                        CarsCard(
                          cars: _c.status.clients,
                          running: _c.status.running,
                        ),
                        const SizedBox(height: 14),
                        const SectionTitle(
                          'Cómo conectar',
                          icon: Icons.help_outline_rounded,
                        ),
                        HelpCard(ips: _c.localIps, port: _c.status.port),
                        if (!needsSetup) ...[
                          const SizedBox(height: 14),
                          const SectionTitle(
                            'Permisos',
                            icon: Icons.verified_user_outlined,
                          ),
                          PermissionsCard(c: _c),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
