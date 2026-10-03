# Pixel Car Player — Plan

## Contexto del hardware (tableta del carro)

| Dato | Valor (de la pantalla "Información") |
|------|------|
| Programa | v.23.07.31A_3.0[1711] — "máquina universal" (head unit chino genérico) |
| Plataforma | K24 (2023/08/03) — APPVER K2401_NWD |
| MCU | V3.6-FF01-20230217 (sin CAN box) |
| Bluetooth | XR829 V2.0 (chip combo WiFi+BT de Allwinner) |

Implicaciones:

- El audio del celular llega por **Bluetooth A2DP** al módulo del radio; la app de música BT
  de fábrica muestra muy poco (título a veces, sin carátula, sin letras).
- Las apps de terceros **no** pueden leer AVRCP del módulo BT propietario de forma fiable.
- Por eso: el **celular** (con Spotify) lee los metadatos reales de Spotify y los **transmite**
  a la tableta por un canal de datos aparte. La tableta solo muestra y controla.

## Arquitectura

Un solo proyecto Flutter (`pixel_car_player`) con dos modos, elegidos al primer arranque:

```
 ┌──────────── Celular (modo "Transmisor") ─────────────┐        ┌──────── Tableta (modo "Pantalla") ───────┐
 │ Spotify ─► MediaSession                              │        │                                          │
 │   └─► TransmitterService (Kotlin, foreground)        │  TCP   │ LinkClient (Dart)                        │
 │        • lee título/artista/álbum/carátula/posición  │ ─────► │   • descubre por beacon UDP / gateway /   │
 │        • busca letras sincronizadas en LRCLIB        │  JSON  │     IP manual, o RFCOMM (BT)              │
 │        • servidor TCP :47321 + beacon UDP :47322     │ ◄───── │ CarController ─► CarPlayerScreen         │
 │        • servidor RFCOMM (BT clásico)                │  cmds  │   (pantalla completa estilo Harmonix:    │
 │        • ejecuta play/pause/next/prev/seek           │        │    portada, letras sync, wavy slider)    │
 │ Flutter UI: estado, permisos, autos conectados       │        │ Fallback: MediaSession local del radio   │
 └──────────────────────────────────────────────────────┘        └──────────────────────────────────────────┘
```

- El transmisor del celular es **100 % nativo (Kotlin)** para que siga vivo con Spotify en primer
  plano y la pantalla apagada.
- La tableta corre la UI en Flutter (siempre en primer plano en el carro).
- Transporte: líneas JSON (ver `CONTRACT.md`). Dos caminos:
  1. **Wi-Fi** (recomendado): tableta conectada al hotspot del celular o a la misma red.
     Descubrimiento automático por beacon UDP + IP del gateway (= el celular si es hotspot) + IP manual.
  2. **Bluetooth RFCOMM**: si el Android de la tableta expone el adaptador BT estándar,
     se conecta al celular emparejado sin Wi-Fi.

## UI de la tableta (basada en `harmonix/lib/presentation/screens/player/full_player_screen.dart`)

Horizontal, pensada para tocar manejando:

- Fondo: carátula difuminada + color dominante (palette) sobre azul marino Harmonix.
- Izquierda: carátula grande con sombra/glow del color de acento (Hero, esquinas 28).
- Derecha: título, artista (accentBright), álbum; letras sincronizadas con auto-scroll,
  línea activa grande y brillante (AnimatedDefaultTextStyle como Harmonix).
- Abajo: WavySlider de Harmonix + tiempos + controles grandes (prev / play gradiente / next).
- Barra superior: reloj, chip de conexión (nombre del celular, ícono Wi-Fi/BT), ajustes.
- Modo "solo letras" a pantalla completa (tocar letras).
- Pantalla de espera "Esperando al celular…" con instrucciones e IP.

## Subagentes

| Agente | Modelo | Alcance (dueño de) |
|--------|--------|--------------------|
| Nativo Android | opus | `android/**` (Kotlin: MediaSession, NotificationListener, TransmitterService, RFCOMM, canales) |
| UI tableta + enlace | opus | `lib/car/**`, `lib/data/link/**`, `lib/data/demo/**` |
| UI celular + CI + docs | sonnet | `lib/phone/**`, `lib/setup/**`, `.github/**`, `README.md` |
| Orquestador (yo) | — | `lib/core/**`, `lib/data/bridge/**`, `lib/main.dart`, compilación, capturas, integración |

## Verificación

- `flutter analyze` + `flutter test` (parser de protocolo/LRC).
- `flutter build apk --release` en el contenedor y en GitHub Actions (APK como Release Beta).
- Capturas: build web con `?mode=car&demo=1` a resoluciones de tableta (1024×600, 1280×720, 2000×1200).
