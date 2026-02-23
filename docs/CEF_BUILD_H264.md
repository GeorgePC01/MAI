# Compilar CEF con H.264 (Proprietary Codecs)

## Por que es necesario

Microsoft Teams requiere H.264 para screen sharing (VBSS - Video-Based Screen Sharing).
El build estandar de CEF de Spotify CDN NO incluye codecs propietarios (H.264, AAC).
Confirmado en CEF Issue #3910: la unica solucion es recompilar CEF.

## Maquina de Build

- **Mac Mini 2018** (Intel, 64GB RAM, macOS 15.7.4 Sequoia)
- **Xcode 16.3** instalado en `/Applications/Xcode.app`
- **Disco**: ~174GB libres (justo, considerar SSD externo de 256GB+)
- **Target**: Cross-compilar ARM64 para MacBook Pro M2 Pro

## Pasos

### 1. Instalar depot_tools

```bash
cd ~
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$HOME/depot_tools:$PATH"
echo 'export PATH="$HOME/depot_tools:$PATH"' >> ~/.zshrc
```

### 2. Preparar directorio de build

```bash
mkdir -p ~/cef_build
cd ~/cef_build
curl -O https://raw.githubusercontent.com/chromiumembedded/cef/master/tools/automate/automate-git.py
```

### 3. Compilar (dejar corriendo de noche, 4-8 horas)

```bash
cd ~/cef_build

export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome use_thin_lto=false symbol_level=0"
export CEF_ARCHIVE_FORMAT=tar.bz2

python3 automate-git.py \
  --download-dir=~/cef_build \
  --branch=7632 \
  --minimal-distrib \
  --client-distrib \
  --force-clean \
  --arm64-build \
  --no-debug-build \
  --x64-build=false
```

**Notas sobre flags**:
- `branch=7632`: Chromium 145.0.7632.x (coincide con nuestro CEF 145.0.23)
- `proprietary_codecs=true ffmpeg_branding=Chrome`: Habilita H.264 + AAC
- `symbol_level=0`: Reduce tamano de build artifacts ~30-40GB
- `--no-debug-build`: Solo Release (ahorra tiempo y disco)
- `--arm64-build`: Cross-compila para Apple Silicon
- `--x64-build=false`: No compilar x86_64 (no lo necesitamos)
- `use_thin_lto=false`: Evita problemas de linker en cross-compilation

### 4. Encontrar el framework compilado

```bash
# El framework estara en algo como:
find ~/cef_build -name "Chromium Embedded Framework.framework" -type d 2>/dev/null
# Tipicamente en: ~/cef_build/chromium/src/out/Release_GN_arm64/
# O en el distrib: ~/cef_build/chromium/src/cef/binary_distrib/
```

### 5. Copiar al MacBook Pro

```bash
# Opcion A: AirDrop el framework (~292MB)
# Opcion B: USB
# Opcion C: Red local
scp -r "Chromium Embedded Framework.framework" george@macbookpro:~/Documents/MAI/Frameworks/
```

### 6. Reconstruir MAI en el MacBook Pro

```bash
cd ~/Documents/MAI

# Reemplazar el framework viejo
rm -rf "Frameworks/Chromium Embedded Framework.framework"
# (copiar el nuevo aqui)

# Rebuild
make clean && make app
```

### 7. Limpiar JS spoofing de CEFBridge.mm

Despues de verificar que Teams funciona, eliminar de CEFBridge.mm:
- Spoof H.264 en getCapabilities (seccion `__maiCodecSpoofed`)
- Spoof permissions.query (seccion `__maiPermSpoofed`)
- Spoof displaySurface en getSettings (seccion `__maiTrackSpoofed`)
- SDP H.264 removal (`maiRemoveH264` y los interceptores de setLocalDescription/setRemoteDescription)
- setCodecPreferences injection
- Mantener: logging diagnostico de WebRTC (addTrack, createOffer, etc.)

## Alternativa: Hardware-Only H.264 (sin licencia)

Si preocupan las licencias de H.264 para distribucion:

```bash
export GN_DEFINES="is_official_build=true proprietary_codecs=true symbol_level=0"
# SIN ffmpeg_branding=Chrome
```

Esto usa macOS VideoToolbox para H.264 hardware encode/decode.
Requiere un patch en `media/BUILD.gn` (ver CEF Issue #3559).
AAC audio NO funcionara, pero Teams usa Opus para audio (ya soportado).

## Referencias

- [CEF Issue #3910](https://github.com/chromiumembedded/cef/issues/3910) - Teams screen sharing fix confirmado
- [CEF Issue #3559](https://github.com/chromiumembedded/cef/issues/3559) - Hardware-only proprietary codecs
- [CEF Build Guide](https://bitbucket.org/chromiumembedded/cef/wiki/AutomatedBuildSetup.md)
- [teams-for-linux](https://github.com/IsmaelMartinez/teams-for-linux) - Referencia de implementacion funcional

## Espacio en Disco

| Componente | Tamano |
|-----------|--------|
| Chromium source checkout | ~35 GB |
| Build artifacts (Release, symbol_level=0) | ~60-80 GB |
| CEF tools/deps | ~10 GB |
| **Total estimado** | **~105-125 GB** |

Con 174GB libres y optimizaciones (symbol_level=0, no debug), deberia alcanzar.
Para mayor seguridad, usar SSD externo de 256GB+ via USB-C/Thunderbolt 3.
