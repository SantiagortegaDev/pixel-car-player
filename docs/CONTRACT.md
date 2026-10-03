# Contratos entre componentes

Fuente de verdad para Dart ⇄ Kotlin y celular ⇄ tableta. Cambios aquí primero.

## 1. Protocolo de enlace (celular ⇄ tableta)

- Transporte: TCP puerto **47321** o RFCOMM (UUID `7c1e3a52-5b8e-4f0a-9d3c-2f6b8a4e91d7`, nombre `PixelCarPlayer`).
- Encoding: **una línea JSON UTF-8 por mensaje**, terminada en `\n`. Campo `t` = tipo.
- Mensajes desconocidos se ignoran. Versión de protocolo `v: 1`.

### Celular → tableta

| `t` | Campos | Cuándo |
|-----|--------|--------|
| `hello` | `v`, `device` (modelo del celular), `source` (paquete, ej. `com.spotify.music`) | al conectar |
| `track` | `id` (hash estable de título+artista+álbum+duración), `title`, `artist`, `album`, `durationMs`, `source` | cambio de canción y al conectar |
| `art` | `id` (id del track), `mime` (`image/jpeg`), `b64` (JPEG ≤ 640 px, calidad 85) | tras `track` si hay carátula |
| `state` | `playing` (bool), `positionMs`, `speed` (double) | cambio de estado, cada 5 s mientras suena, y al conectar |
| `lyrics` | `id`, `status` (`ok` \| `not_found` \| `loading`), `synced` (bool), `lines`: `[{ "ms": int, "text": str }]` | cuando se resuelven (LRCLIB) |
| `queue` | `items`: `[{ "title": str, "artist": str }]` — próximas canciones de la cola del reproductor (después del ítem activo si se conoce, si no toda la cola; máx 20; `[]` si no hay cola) | al conectar / `resync` (tras `lyrics`), al cambiar la cola y al cambiar de canción |
| `ping` | — | cada 10 s |

La tableta interpola la posición con su propio reloj desde el instante en que recibe `state`
(no se compara el reloj del celular).

### Tableta → celular

| `t` | Campos |
|-----|--------|
| `hello` | `v`, `device` |
| `cmd` | `action`: `play` \| `pause` \| `toggle` \| `next` \| `previous` \| `seek`; `positionMs` (solo `seek`) |
| `pong` | — (respuesta a `ping`) |
| `resync` | — (pide reenviar `track`, `art`, `state`, `lyrics`, `queue`) |

### Descubrimiento (Wi-Fi)

- El celular envía cada 2 s un **beacon UDP** al puerto **47322** (broadcast de cada interfaz IPv4
  activa + `255.255.255.255`): `{"t":"beacon","v":1,"device":"Pixel 8","port":47321}`.
- La tableta intenta en paralelo: IP del beacon, IP del **gateway** Wi-Fi (caso hotspot del celular),
  IP manual guardada. Primera conexión TCP exitosa gana. Reintento con backoff (1 s → 10 s).
- Si no llega `ping` en 25 s → se considera caída y se reconecta.

## 2. Canal nativo (Flutter ⇄ Kotlin)

`MethodChannel("pcp/native")` — en web/desktop no existe: el código Dart debe protegerse con
`kIsWeb` / try-catch `MissingPluginException`.

| Método | Args | Retorno | Lado |
|--------|------|---------|------|
| `getDeviceInfo` | — | `{model, manufacturer, sdkInt}` | ambos |
| `hasNotificationAccess` | — | `bool` | ambos |
| `openNotificationAccessSettings` | — | — | ambos |
| `requestRuntimePermissions` | — | `{bluetoothConnect: bool, postNotifications: bool}` | ambos |
| `setKeepScreenOn` | `{on: bool}` | — | tableta |
| `startTransmitter` | `{sourcePackage: String?}` (`null` = cualquier app de música; default Spotify) | `bool` | celular |
| `stopTransmitter` | — | — | celular |
| `getTransmitterStatus` | — | ver evento `transmitterStatus` | celular |
| `getGatewayIp` | — | `String?` | tableta |
| `getLocalIps` | — | `List<String>` | ambos |
| `acquireMulticastLock` / `releaseMulticastLock` | — | — | tableta |
| `getBondedDevices` | — | `[{name, address}]` | tableta |
| `connectRfcomm` | `{address}` | `bool` (conectó) | tableta |
| `sendRfcomm` | `{line: String}` (sin `\n`) | `bool` | tableta |
| `disconnectRfcomm` | — | — | tableta |
| `startLocalMediaWatch` | — | `bool` | tableta |
| `stopLocalMediaWatch` | — | — | tableta |
| `localMediaCommand` | `{action, positionMs?}` (mismas acciones que `cmd`) | `bool` | tableta |
| `canDrawOverlays` | — | `bool` (`true` bajo API 23) | tableta |
| `openOverlaySettings` | — | — (abre `ACTION_MANAGE_OVERLAY_PERMISSION`; fallback a info de la app) | tableta |
| `openBatteryOptimizationSettings` | — | — (abre `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`; fallback a info de la app) | tableta |

**Inicio automático**: `BootReceiver` (exportado, `RECEIVE_BOOT_COMPLETED`) escucha `BOOT_COMPLETED`,
`LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED` y broadcasts "ACC on" de head units
(`android.intent.action.ACC_ON`, `com.fyt.boot.ACCON`, `com.microntek.bootcheck`,
`autochips.intent.action.QB_POWERON`). Lee `FlutterSharedPreferences`: `flutter.app_mode == "car"` y
`flutter.car_autostart == true` (Boolean); opcional `flutter.car_autostart_delay` (segundos, Long, default 3).
Tras el delay lanza `MainActivity` (`FLAG_ACTIVITY_NEW_TASK`). En Android 10+ requiere `SYSTEM_ALERT_WINDOW`
(se intenta igual sin el permiso; errores se registran con tag `PCP`).

`EventChannel("pcp/events")` — un único stream de `Map` con campo `type`:

| `type` | Campos |
|--------|--------|
| `transmitterStatus` | `running` (bool), `port`, `ips: [String]`, `clients: [{device, transport: "wifi"\|"bt", address}]`, `session: {package, title, artist, playing}?`, `lyricsStatus` |
| `rfcomm` | `event`: `connected` (`name`, `address`) \| `line` (`data`: String JSON) \| `disconnected` (`reason`) |
| `localMedia` | `package`, `title`, `artist`, `album`, `durationMs`, `playing`, `positionMs`, `art` (`Uint8List?` PNG/JPEG) |

## 3. Paquete / ids

- applicationId: `com.santiagortega.pixelcarplayer`
- Nombre visible: **Pixel Car Player**
- Kotlin package: `com.santiagortega.pixelcarplayer`
