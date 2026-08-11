# Wispr Flow en Arch Linux / Hyprland

Este proyecto construye **Wispr Flow 1.6.447** para Linux a partir del paquete
oficial de Windows. No es una reimplementacion de Whisper ni usa Wine: conserva
el cliente Electron, el login, la cuenta Pro y los servicios cloud de Wispr, y
sustituye solo la integracion Win32 por un helper Linux de codigo abierto.

Wispr no publica ni soporta oficialmente una version Linux. El resultado es un
port comunitario y puede romperse con una futura actualizacion del servicio.

## Que necesitas copiar

No descargues una AppImage, un instalador de Windows ni Electron manualmente.
`install.sh` descarga y construye todo lo necesario. Debes conservar junta la
carpeta completa de este proyecto; no copies solamente `install.sh`, porque el
instalador tambien utiliza los scripts de `bin/`.

La carpeta minima debe contener:

```text
whsprflow-arch/
|-- install.sh
|-- uninstall.sh
|-- bin/
|   |-- wispr-flow
|   `-- wispr-flow-configure
|-- tests/
|   `-- smoke.sh
`-- README.md
```

## Requisitos

- Arch Linux x86_64 actualizado.
- Una sesion de Hyprland iniciada con tu usuario normal.
- Conexion a Internet durante la instalacion.
- Acceso a `sudo` para instalar paquetes, la aplicacion y las reglas udev.
- Aproximadamente 2.5 GB libres durante la construccion.
- Una cuenta de Wispr para iniciar sesion al terminar.

No ejecutes el instalador ni la aplicacion completa con `sudo`. El propio script
pedira `sudo` solamente para las operaciones que lo necesitan.

## Instalacion recomendada

1. Abre una terminal dentro de Hyprland y entra en la carpeta del proyecto. Usa
   la ruta real en la que tengas `whsprflow-arch`:

   ```bash
   cd /ruta/donde/tienes/whsprflow-arch
   ```

2. Comprueba que estas en la carpeta correcta:

   ```bash
   ls
   ```

   Debes ver, como minimo, `install.sh`, `uninstall.sh`, `bin`, `tests` y
   `README.md`.

3. Da permisos de ejecucion a los scripts:

   ```bash
   chmod +x install.sh uninstall.sh bin/* tests/*
   ```

4. Ejecuta la prueba local de los scripts:

   ```bash
   ./tests/smoke.sh
   ```

   El resultado debe terminar con `Smoke tests OK`.

5. Cierra cualquier instancia anterior de Wispr Flow y ejecuta la instalacion:

   ```bash
   ./install.sh
   ```

6. Introduce tu clave de `sudo` cuando se solicite y confirma la instalacion de
   paquetes de `pacman`. El instalador hace automaticamente todo esto:

   - instala las dependencias de Arch, incluido XWayland y `wl-clipboard`;
   - descarga el cliente oficial de Wispr Flow `1.6.447`;
   - descarga Electron Linux `42.3.0`;
   - descarga el helper Linux `0.1.2` y el modulo SQLite compatible;
   - comprueba el SHA-256 de cada binario antes de utilizarlo;
   - aplica y verifica los parches Linux;
   - instala la aplicacion en `/opt/wispr-flow`;
   - instala el comando `/usr/local/bin/wispr-flow`;
   - registra el protocolo de login `wispr-flow:` y la entrada del menu;
   - configura `Ctrl+Super` como push-to-talk;
   - instala las reglas udev para `/dev/uinput` y los teclados;
   - anade tu usuario al grupo `input` si todavia no pertenece a el.

   Las descargas verificadas quedan en `~/.cache/whsprflow-arch`, de modo que una
   reinstalacion no tiene que descargarlas otra vez. Los directorios temporales
   de construccion se borran automaticamente.

7. Comprueba que la salida termina de forma parecida a esta:

   ```text
   ==> Instalacion terminada
   Version:      1.6.447
   Tipo:         system
   Ejecutable:   /usr/local/bin/wispr-flow
   ```

8. Si el instalador ha anadido tu usuario al grupo `input`, cierra completamente
   la sesion de Hyprland y vuelve a entrar. No basta con cerrar la terminal. No
   es necesario reiniciar el equipo, aunque reiniciarlo tambien sirve.

## Comprobar la instalacion

Ya dentro de una sesion nueva de Hyprland, ejecuta como usuario normal:

```bash
command -v wispr-flow
wispr-flow --doctor
```

El primer comando debe mostrar `/usr/local/bin/wispr-flow`. En el diagnostico,
comprueba especialmente estas lineas:

- `/dev/uinput` debe ser escribible;
- al menos un dispositivo de teclado debe ser legible;
- el helper Linux debe arrancar correctamente;
- Electron debe indicar la version `42.3.0`;
- el callback `wispr-flow:` debe aparecer registrado;
- el atajo PTT debe aparecer como `Ctrl+Super`.

Un aviso de AT-SPI al principio de la sesion puede ser recuperable; los fallos de
`/dev/uinput`, teclado, helper o callback deben corregirse antes de usar Flow.
Si los permisos de entrada siguen fallando despues de volver a entrar, ejecuta
de nuevo `./install.sh` desde la carpeta del proyecto y repite el diagnostico.

## Primer inicio y login

1. Inicia la aplicacion desde el menu de Hyprland o desde una terminal:

   ```bash
   wispr-flow
   ```

2. Pulsa la opcion de iniciar sesion. Flow abrira el navegador.
3. Completa el login en la web de Wispr.
4. El navegador debe abrir automaticamente un enlace `wispr-flow:` que vuelve a
   la aplicacion. No copies tokens ni edites archivos manualmente.
5. Selecciona el microfono en Flow y prueba el dictado manteniendo
   `Ctrl+Super`.
6. Prueba primero en un editor de texto sencillo y despues en tus aplicaciones
   Wayland habituales.

Para consultar el registro si algo falla:

```bash
wispr-flow --logs
```

El perfil, la sesion y las preferencias se guardan en
`~/.config/Wispr Flow/`. Reinstalar conserva ese directorio.

## Hyprland

Electron 42 no implementa `setIgnoreMouseEvents()` en Wayland nativo. La Flow
Bar transparente puede bloquear clics en un rectangulo de 490x440. Por eso el
wrapper usa XWayland solo para las ventanas de Flow y oculta la Flow Bar; el
helper conserva `WAYLAND_DISPLAY` y sigue pegando en aplicaciones Wayland con
`uinput`, `wl-clipboard` y AT-SPI.

Comandos utiles:

```bash
wispr-flow --fix-shortcut  # repara un atajo Fn heredado de macOS
wispr-flow --flow-bar on   # muestra la barra (puede interceptar clics)
wispr-flow --flow-bar off
wispr-flow --logs
```

Para probar las ventanas Wayland nativas:

```bash
WISPR_FLOW_NATIVE_WAYLAND=1 wispr-flow
```

## Seguridad

En Wayland, el helper necesita escribir en `/dev/uinput` para insertar texto y
leer eventos de teclado para el atajo global. La regla limita la lectura a los
dispositivos marcados por udev como teclado, pero cualquier proceso ejecutado
con tu usuario podria aprovechar esos permisos. Es una limitacion conocida del
port hasta que disponga de un backend estable de GlobalShortcuts portal.

La instalacion de usuario sin sandbox SUID esta disponible solo como fallback:

```bash
./install.sh --user
```

## Desinstalar

```bash
./uninstall.sh
./uninstall.sh --purge  # tambien borra sesion local, preferencias y cache
```

## Verificacion

```bash
./tests/smoke.sh
```

La prueba real realizada durante el desarrollo confirmo: Electron nativo,
version `1.6.447`, 138 migraciones SQLite, helper Linux listo y AudioContext
inicializado. La captura y el pegado global deben validarse en tu sesion real de
Hyprland, porque el entorno automatizado disponible no es tu escritorio Arch.

## Fuentes

- Cliente oficial: <https://dl.wisprflow.com/wispr-flow/win32/x64/RELEASES>
- Port Linux: <https://github.com/wispr-flow-linux/wispr-flow-linux>
- Helper Linux: <https://github.com/wispr-flow-linux/helper>
- Requisitos oficiales: <https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements>
