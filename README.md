# Sound Control

App de barra de menús para macOS que permite controlar el volumen de cada aplicación por separado, además del volumen general del sistema.

## Funcionalidades

- **Volumen general**: barra para subir/bajar el volumen del dispositivo de salida actual y botón de silencio.
- **Volumen por aplicación**: cada app que emite sonido aparece con su icono y su propia barra de volumen (0–100 %) y botón de silencio.
- **Recuerda tus ajustes**: si bajas el volumen de una app, se vuelve a aplicar automáticamente la próxima vez que reproduzca sonido.
- **Abrir al iniciar sesión**: casilla para que la app se lance automáticamente al arrancar el Mac.
- Vive solo en la barra superior (sin icono en el Dock).

## Requisitos

- macOS 14.2 o superior
- Xcode / Command Line Tools con Swift 5.9+

## Compilar e instalar

```bash
./scripts/build-app.sh            # genera build/Sound Control.app
./scripts/build-app.sh --install  # además la copia a /Applications y la abre
```

La primera vez que cambies el volumen de una aplicación, macOS pedirá permiso para **grabar el audio del sistema**. Es necesario para poder ajustar el volumen de cada app. Puedes revisarlo en *Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema*.

> Como la app se firma localmente (ad-hoc), puede que macOS vuelva a pedir el permiso tras recompilarla.

## Cómo funciona

El volumen por aplicación usa los *process taps* de Core Audio (macOS 14.2+): cuando una app tiene un volumen distinto de 100 %, se intercepta su audio, se silencia la salida original y se reproduce de nuevo por el dispositivo de salida con la ganancia elegida. Las apps al 100 % no se tocan, por lo que no hay ningún procesamiento extra.

## Estructura

```
Sources/SoundControl/
├── SoundControlApp.swift         # Punto de entrada y MenuBarExtra
├── ContentView.swift             # Interfaz
├── SystemVolumeController.swift  # Volumen general del dispositivo de salida
├── AppVolumeController.swift     # Detección de apps con audio y gestión de volúmenes
├── ProcessTap.swift              # Tap de Core Audio + dispositivo agregado por app
├── LaunchAtLogin.swift           # Inicio automático (SMAppService)
└── CoreAudioUtils.swift          # Utilidades de Core Audio
```
