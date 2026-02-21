# Pasos para compilar CEF con H.264 en Mac Mini 2018

## Contexto

**Problema**: Teams screen sharing no funciona en MAI porque CEF estandar no tiene H.264.
**Solucion**: Compilar CEF con codecs propietarios en el Mac Mini (64GB RAM).
**Resultado**: Framework de ~292MB que se copia al MacBook Pro M2 Pro.

## Estado del Mac Mini

- Mac Mini 2018, Intel, 64GB RAM
- macOS 15.7.4 Sequoia
- Xcode 16.3 instalado en /Applications/Xcode.app
- Disco interno: 233GB total, **87GB libres** (NO suficiente para build)
- Usuario: jorgeramos

### Discos disponibles

| Disco | Tamaño | Disponible | Montado en |
|-------|--------|------------|------------|
| Interno | 233GB | 87GB | `/` |
| Jorge | 465GB | 208GB | `/Volumes/Jorge` |
| **KINGSTON** | **932GB** | **756GB** | **`/Volumes/KINGSTON`** |

**Disco elegido para build: KINGSTON** (756GB libres, espacio de sobra para los ~100-150GB que necesita el build)

---

## Paso 0: Verificar disco externo

Antes de empezar, asegurar que el KINGSTON esta conectado y montado:

```bash
df -h | grep KINGSTON
# Debe mostrar: /dev/disk2s1  932Gi  175Gi  756Gi  19%  /Volumes/KINGSTON

# Crear directorio de build
mkdir -p /Volumes/KINGSTON/cef_build
```

Si el KINGSTON no aparece, conectarlo por USB y verificar en Finder o Disk Utility.

## Paso 1: Instalar depot_tools

```bash
cd ~
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$HOME/depot_tools:$PATH"
echo 'export PATH="$HOME/depot_tools:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verificar:
```bash
which gclient
# Debe mostrar ~/depot_tools/gclient
```

## Paso 2: Preparar directorio y descargar script

```bash
mkdir -p /Volumes/KINGSTON/cef_build
cd /Volumes/KINGSTON/cef_build
curl -O https://raw.githubusercontent.com/chromiumembedded/cef/master/tools/automate/automate-git.py
ls -la automate-git.py
# Debe mostrar el archivo descargado
```

## Paso 3: Lanzar el build (DEJAR DE NOCHE - 4-8 horas)

```bash
cd /Volumes/KINGSTON/cef_build

export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome use_thin_lto=false symbol_level=0"
export CEF_ARCHIVE_FORMAT=tar.bz2
```

**IMPORTANTE**: Este comando descarga ~35GB de source code y luego compila durante horas.
No cerrar la terminal. Usar `caffeinate` para evitar que el Mac se duerma:

```bash
caffeinate -s python3 automate-git.py \
  --download-dir=/Volumes/KINGSTON/cef_build \
  --branch=7632 \
  --minimal-distrib \
  --client-distrib \
  --force-clean \
  --arm64-build \
  --no-debug-build
```

O alternativamente, correr en background con nohup:

```bash
cd /Volumes/KINGSTON/cef_build
export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome use_thin_lto=false symbol_level=0"
export CEF_ARCHIVE_FORMAT=tar.bz2

nohup caffeinate -s python3 automate-git.py \
  --download-dir=/Volumes/KINGSTON/cef_build \
  --branch=7632 \
  --minimal-distrib \
  --client-distrib \
  --force-clean \
  --arm64-build \
  --no-debug-build \
  > /Volumes/KINGSTON/cef_build/build.log 2>&1 &

# Monitorear progreso:
tail -f /Volumes/KINGSTON/cef_build/build.log
```

### Monitorear temperatura durante el build

```bash
# En otra terminal:
while true; do echo "$(date): $(osx-cpu-temp)"; sleep 60; done
# Normal: 70-90°C bajo carga. Preocuparse si pasa de 100°C.
```

## Paso 4: Copiar framework al MacBook Pro

Cuando el build termine, buscar el framework:

```bash
find /Volumes/KINGSTON/cef_build -name "Chromium Embedded Framework.framework" -type d 2>/dev/null
```

Copiar al MacBook Pro (elegir una opcion):

**Opcion A - AirDrop**: Comprimir y enviar por AirDrop
```bash
# En el Mac Mini:
cd <directorio donde esta el framework>
tar czf ~/Desktop/CEF_H264_arm64.tar.gz "Chromium Embedded Framework.framework"
# Enviar ~/Desktop/CEF_H264_arm64.tar.gz por AirDrop
```

**Opcion B - Red local (scp)**:
```bash
scp -r "Chromium Embedded Framework.framework" george@<ip-macbook>:~/Documents/MAI/Frameworks/
```

**Opcion C - USB**: Copiar a un USB y transferir

---

## Despues en el MacBook Pro M2 Pro

```bash
cd ~/Documents/MAI

# Reemplazar framework viejo
rm -rf "Frameworks/Chromium Embedded Framework.framework"
# Pegar el nuevo framework aqui

# Rebuild MAI
make clean && make app
```

Verificar: Abrir Teams > unirse a llamada > compartir pantalla > debe funcionar sin error.

---

## Post-build: Limpiar codigo JS de spoofing

Una vez confirmado que Teams funciona con el nuevo framework, eliminar de `CEFBridge.mm`:
- H.264 spoof en getCapabilities
- SDP H.264 removal
- setCodecPreferences injection
- displaySurface spoof
- permissions.query spoof

Estos parches JS ya no seran necesarios con codecs propietarios nativos.

## Referencias

- CEF Issue #3910: https://github.com/chromiumembedded/cef/issues/3910
- CEF Issue #3559: https://github.com/chromiumembedded/cef/issues/3559
- CEF Build Guide: https://bitbucket.org/chromiumembedded/cef/wiki/AutomatedBuildSetup.md
