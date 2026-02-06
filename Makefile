# Makefile para MAI Browser

.PHONY: build run clean test help bundle app

# Variables
SWIFT = swift
BUILD_DIR = .build
RELEASE_DIR = $(BUILD_DIR)/release
DEBUG_DIR = $(BUILD_DIR)/arm64-apple-macosx/debug
APP_NAME = MAI
BUNDLE = $(APP_NAME).app

help: ## Muestra esta ayuda
	@echo "MAI Browser - Comandos disponibles:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## Compila el navegador en modo release
	@echo "🔨 Compilando MAI Browser (Release)..."
	@$(SWIFT) build -c release
	@echo "✅ Compilación completada"

build-debug: ## Compila en modo debug
	@echo "🔨 Compilando MAI Browser (Debug)..."
	@$(SWIFT) build
	@echo "✅ Compilación completada: $(DEBUG_DIR)/MAI"

bundle: build-debug ## Crea el .app bundle
	@echo "📦 Creando $(BUNDLE)..."
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(DEBUG_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	@cp Resources/Info.plist $(BUNDLE)/Contents/
	@cp Resources/MAI.entitlements $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@echo "🔐 Firmando app con entitlements..."
	@codesign --force --deep --sign - --entitlements Resources/MAI.entitlements $(BUNDLE) 2>/dev/null || echo "⚠️  Firma sin entitlements (se requiere certificado de desarrollador para passkeys)"
	@touch $(BUNDLE)
	@echo "✅ Bundle creado: $(BUNDLE)"

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
	@find Sources src -name "*.swift" 2>/dev/null | wc -l
	@echo ""
	@echo "Líneas de código:"
	@find Sources src -name "*.swift" -exec cat {} \; 2>/dev/null | wc -l

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
