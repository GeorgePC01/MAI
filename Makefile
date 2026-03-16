# Makefile para MAI Browser
# v0.5.0 - CEF Hybrid Engine + Anti-RE Hardening

.PHONY: build run clean test help bundle app helper cef-check encrypt-scripts obfuscate-scripts

# Variables
SWIFT = swift
BUILD_DIR = .build
RELEASE_DIR = $(BUILD_DIR)/release
DEBUG_DIR = $(BUILD_DIR)/arm64-apple-macosx/debug
APP_NAME = MAI
BUNDLE = $(APP_NAME).app
CEF_FRAMEWORK = Frameworks/Chromium\ Embedded\ Framework.framework
CEF_INCLUDE = Frameworks/cef_include
HELPER_NAME = MAI Helper

help: ## Muestra esta ayuda
	@echo "MAI Browser - Comandos disponibles:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

cef-check: ## Verifica que CEF framework existe
	@if [ ! -d "Frameworks/Chromium Embedded Framework.framework" ]; then \
		echo "❌ CEF framework no encontrado en Frameworks/"; \
		echo "   Descarga desde: https://cef-builds.spotifycdn.com/index.html"; \
		echo "   Platform: macOS ARM64, Distribution: Minimal"; \
		exit 1; \
	fi
	@echo "✅ CEF framework encontrado"

build: cef-check ## Compila el navegador en modo release
	@echo "🔨 Compilando MAI Browser (Release)..."
	@$(SWIFT) build -c release
	@echo "✅ Compilación completada"

build-debug: cef-check ## Compila en modo debug
	@echo "🔨 Compilando MAI Browser (Debug)..."
	@$(SWIFT) build
	@echo "✅ Compilación completada: $(DEBUG_DIR)/MAI"

helper: cef-check ## Compila el CEF helper subprocess
	@echo "🔨 Compilando MAI Helper..."
	@mkdir -p $(BUILD_DIR)/helper
	@clang -o $(BUILD_DIR)/helper/"$(HELPER_NAME)" \
		Sources/MAIHelper/main.m \
		-framework Foundation \
		-fobjc-arc \
		-mmacosx-version-min=13.0
	@echo "✅ Helper compilado: $(BUILD_DIR)/helper/$(HELPER_NAME)"

bundle: build-debug helper ## Crea el .app bundle con CEF
	@echo "📦 Creando $(BUNDLE)..."
	@rm -rf $(BUNDLE) /tmp/_mai_sign
	@mkdir -p /tmp/_mai_sign/$(BUNDLE)/Contents/MacOS
	@mkdir -p /tmp/_mai_sign/$(BUNDLE)/Contents/Resources
	@mkdir -p "/tmp/_mai_sign/$(BUNDLE)/Contents/Frameworks"
	@# Copiar ejecutable principal (sin .md — codesign los rechaza)
	@ditto --norsrc $(DEBUG_DIR)/$(APP_NAME) /tmp/_mai_sign/$(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@chmod +x /tmp/_mai_sign/$(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist /tmp/_mai_sign/$(BUNDLE)/Contents/
	@cp Resources/MAI.entitlements /tmp/_mai_sign/$(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@cp assets/AppIcon.icns /tmp/_mai_sign/$(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@# Copiar CEF framework
	@echo "📦 Copiando Chromium Embedded Framework..."
	@ditto --norsrc "Frameworks/Chromium Embedded Framework.framework" "/tmp/_mai_sign/$(BUNDLE)/Contents/Frameworks/Chromium Embedded Framework.framework"
	@echo "📦 Creando 5 CEF Helper bundles..."
	@/bin/bash -c '\
		SIGNDIR="/tmp/_mai_sign"; \
		create_helper() { \
			local hname="$$1" bundleid="$$2"; \
			echo "  → $$hname.app ($$bundleid)"; \
			mkdir -p "$$SIGNDIR/$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/MacOS"; \
			ditto --norsrc $(BUILD_DIR)/helper/"$(HELPER_NAME)" "$$SIGNDIR/$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/MacOS/$$hname"; \
			chmod +x "$$SIGNDIR/$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/MacOS/$$hname"; \
			printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>CFBundleExecutable</key>\n\t<string>%s</string>\n\t<key>CFBundleIdentifier</key>\n\t<string>%s</string>\n\t<key>CFBundleName</key>\n\t<string>%s</string>\n\t<key>CFBundlePackageType</key>\n\t<string>APPL</string>\n\t<key>LSUIElement</key>\n\t<true/>\n</dict>\n</plist>\n" "$$hname" "$$bundleid" "$$hname" > "$$SIGNDIR/$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/Info.plist"; \
		}; \
		create_helper "$(HELPER_NAME)" "com.mai.browser.helper"; \
		create_helper "$(HELPER_NAME) (Alerts)" "com.mai.browser.helper.alerts"; \
		create_helper "$(HELPER_NAME) (GPU)" "com.mai.browser.helper.gpu"; \
		create_helper "$(HELPER_NAME) (Plugin)" "com.mai.browser.helper.plugin"; \
		create_helper "$(HELPER_NAME) (Renderer)" "com.mai.browser.helper.renderer"'
	@echo "✅ 5 helper bundles creados"
	@# ── Strip symbols + remove stray files ──
	@echo "🔒 Stripping symbols..."
	@strip -x /tmp/_mai_sign/$(BUNDLE)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@find /tmp/_mai_sign/$(BUNDLE) -name '*.md' -not -path '*/Resources/*' -delete 2>/dev/null || true
	@find /tmp/_mai_sign/$(BUNDLE) -name '.DS_Store' -delete 2>/dev/null || true
	@find /tmp/_mai_sign/$(BUNDLE) -name '._*' -delete 2>/dev/null || true
	@# ── Sign ALL components with hardened runtime (inside-out for macOS 26) ──
	@echo "🔐 Firmando con hardened runtime (deep)..."
	@for helper in /tmp/_mai_sign/$(BUNDLE)/Contents/Frameworks/*.app; do \
		codesign --force --sign - --options runtime "$$helper" 2>/dev/null || true; \
	done
	@codesign --force --sign - --options runtime "/tmp/_mai_sign/$(BUNDLE)/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null || true
	@codesign --force --sign - --options runtime --entitlements Resources/MAI.entitlements /tmp/_mai_sign/$(BUNDLE)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@codesign --force --sign - --options runtime --entitlements Resources/MAI.entitlements /tmp/_mai_sign/$(BUNDLE) 2>/dev/null || echo "⚠️  Firma sin entitlements"
	@codesign --verify --deep --strict /tmp/_mai_sign/$(BUNDLE) 2>/dev/null && echo "✅ Firma verificada" || echo "⚠️  Firma no verificada"
	@# ── Move signed bundle to project directory ──
	@ditto --norsrc /tmp/_mai_sign/$(BUNDLE) $(BUNDLE)
	@rm -rf /tmp/_mai_sign
	@echo "✅ Bundle creado: $(BUNDLE) (con CEF + 5 helpers, firmado)"

app: bundle ## Compila y ejecuta como .app (RECOMENDADO)
	@echo "🚀 Ejecutando $(BUNDLE)..."
	@open $(BUNDLE)

run: app ## Alias para 'app' - ejecuta el navegador correctamente
	@true

run-dev: build-debug ## Ejecuta sin bundle (el foco puede no funcionar)
	@echo "⚠️  Modo desarrollo - el foco puede no funcionar"
	@$(DEBUG_DIR)/MAI

test: ## Ejecuta los tests
	@echo "🧪 Ejecutando tests..."
	@$(SWIFT) test

clean: ## Limpia los archivos de compilación
	@echo "🧹 Limpiando build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -rf $(BUNDLE)
	@echo "✅ Limpieza completada"

xcode: ## Abre el proyecto en Xcode
	@echo "📦 Abriendo en Xcode..."
	@open Package.swift

format: ## Formatea el código Swift
	@echo "💅 Formateando código..."
	@find Sources -name "*.swift" -exec swift-format -i {} \; 2>/dev/null || true
	@echo "✅ Código formateado"

stats: ## Muestra estadísticas del proyecto
	@echo "📊 Estadísticas del proyecto MAI:"
	@echo ""
	@echo "Archivos Swift:"
	@find Sources -name "*.swift" 2>/dev/null | wc -l
	@echo ""
	@echo "Archivos ObjC++:"
	@find Sources -name "*.mm" -o -name "*.m" 2>/dev/null | wc -l
	@echo ""
	@echo "Líneas de código (Swift):"
	@find Sources -name "*.swift" -exec cat {} \; 2>/dev/null | wc -l
	@echo ""
	@echo "Líneas de código (ObjC++):"
	@find Sources -name "*.mm" -o -name "*.m" 2>/dev/null -exec cat {} \; 2>/dev/null | wc -l
	@echo ""
	@echo "CEF Framework:"
	@du -sh "Frameworks/Chromium Embedded Framework.framework" 2>/dev/null || echo "No instalado"

install: bundle ## Instala MAI en /Applications
	@echo "📦 Instalando MAI Browser..."
	@rm -rf /Applications/$(BUNDLE)
	@cp -r $(BUNDLE) /Applications/
	@echo "✅ MAI instalado en /Applications/$(BUNDLE)"

uninstall: ## Desinstala MAI
	@echo "🗑️  Desinstalando MAI Browser..."
	@rm -rf /Applications/$(BUNDLE)
	@echo "✅ MAI desinstalado"

obfuscate-scripts: ## Ofusca los scripts JS (anti-RE)
	@echo "🔒 Ofuscando scripts JS..."
	@swift Tools/obfuscate_scripts.swift
	@echo "✅ Scripts ofuscados"

encrypt-scripts: obfuscate-scripts ## Ofusca + cifra scripts JS (genera EncryptedScripts.swift)
	@echo "🔐 Cifrando scripts ofuscados..."
	@swift Tools/encrypt_scripts.swift
	@echo "✅ EncryptedScripts.swift regenerado"

secure-build: encrypt-scripts bundle ## Build completo con ofuscación + cifrado + hardened runtime

.DEFAULT_GOAL := help
