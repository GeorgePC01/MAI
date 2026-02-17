# Makefile para MAI Browser
# v0.4.0 - CEF Hybrid Engine Support

.PHONY: build run clean test help bundle app helper cef-check

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
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@mkdir -p "$(BUNDLE)/Contents/Frameworks"
	@# Copiar ejecutable principal
	@cp $(DEBUG_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	@cp Resources/Info.plist $(BUNDLE)/Contents/
	@cp Resources/MAI.entitlements $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@# Copiar CEF framework
	@echo "📦 Copiando Chromium Embedded Framework..."
	@cp -R "Frameworks/Chromium Embedded Framework.framework" "$(BUNDLE)/Contents/Frameworks/"
	@# ── Create all 5 CEF helper bundles ──
	@# CEF M128+ requires: Base, Alerts, GPU, Plugin, Renderer
	@# Each is a separate .app with unique bundle ID but same executable binary.
	@# CEF derives subprocess paths from the base helper name by appending (GPU), (Renderer), etc.
	@echo "📦 Creando 5 CEF Helper bundles..."
	@/bin/bash -c '\
		create_helper() { \
			local hname="$$1" bundleid="$$2"; \
			echo "  → $$hname.app ($$bundleid)"; \
			mkdir -p "$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/MacOS"; \
			cp $(BUILD_DIR)/helper/"$(HELPER_NAME)" "$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/MacOS/$$hname"; \
			printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>CFBundleExecutable</key>\n\t<string>%s</string>\n\t<key>CFBundleIdentifier</key>\n\t<string>%s</string>\n\t<key>CFBundleName</key>\n\t<string>%s</string>\n\t<key>CFBundlePackageType</key>\n\t<string>APPL</string>\n\t<key>LSUIElement</key>\n\t<true/>\n</dict>\n</plist>\n" "$$hname" "$$bundleid" "$$hname" > "$(BUNDLE)/Contents/Frameworks/$$hname.app/Contents/Info.plist"; \
			codesign --force --sign - "$(BUNDLE)/Contents/Frameworks/$$hname.app" 2>/dev/null || true; \
		}; \
		create_helper "$(HELPER_NAME)" "com.mai.browser.helper"; \
		create_helper "$(HELPER_NAME) (Alerts)" "com.mai.browser.helper.alerts"; \
		create_helper "$(HELPER_NAME) (GPU)" "com.mai.browser.helper.gpu"; \
		create_helper "$(HELPER_NAME) (Plugin)" "com.mai.browser.helper.plugin"; \
		create_helper "$(HELPER_NAME) (Renderer)" "com.mai.browser.helper.renderer"'
	@echo "✅ 5 helper bundles creados"
	@# ── Strip xattrs and sign ──
	@echo "🔐 Firmando componentes..."
	@/usr/bin/xattr -cr $(BUNDLE) 2>/dev/null || true
	@codesign --force --sign - "$(BUNDLE)/Contents/Frameworks/Chromium Embedded Framework.framework" 2>/dev/null || true
	@codesign --force --sign - --entitlements Resources/MAI.entitlements $(BUNDLE) 2>/dev/null || echo "⚠️  Firma sin entitlements"
	@touch $(BUNDLE)
	@echo "✅ Bundle creado: $(BUNDLE) (con CEF + 5 helpers)"

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

.DEFAULT_GOAL := help
