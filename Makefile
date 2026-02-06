# Makefile para MAI Browser

.PHONY: build run clean test help

# Variables
SWIFT = swift
BUILD_DIR = .build
RELEASE_DIR = $(BUILD_DIR)/release
DEBUG_DIR = $(BUILD_DIR)/debug

help: ## Muestra esta ayuda
	@echo "MAI Browser - Comandos disponibles:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## Compila el navegador en modo release
	@echo "🔨 Compilando MAI Browser (Release)..."
	@$(SWIFT) build -c release
	@echo "✅ Compilación completada: $(RELEASE_DIR)/MAI"

build-debug: ## Compila en modo debug
	@echo "🔨 Compilando MAI Browser (Debug)..."
	@$(SWIFT) build
	@echo "✅ Compilación completada: $(DEBUG_DIR)/MAI"

run: build-debug ## Compila y ejecuta el navegador
	@echo "🚀 Ejecutando MAI Browser...\n"
	@$(DEBUG_DIR)/MAI

test: ## Ejecuta los tests
	@echo "🧪 Ejecutando tests..."
	@$(SWIFT) test

clean: ## Limpia los archivos de compilación
	@echo "🧹 Limpiando build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "✅ Limpieza completada"

xcode: ## Genera proyecto Xcode
	@echo "📦 Generando proyecto Xcode..."
	@$(SWIFT) package generate-xcodeproj
	@echo "✅ Proyecto generado: MAI.xcodeproj"
	@open MAI.xcodeproj

format: ## Formatea el código Swift
	@echo "💅 Formateando código..."
	@find src -name "*.swift" -exec swift-format -i {} \;
	@echo "✅ Código formateado"

stats: ## Muestra estadísticas del proyecto
	@echo "📊 Estadísticas del proyecto MAI:"
	@echo ""
	@echo "Archivos Swift:"
	@find src -name "*.swift" | wc -l
	@echo ""
	@echo "Líneas de código:"
	@find src -name "*.swift" -exec cat {} \; | wc -l
	@echo ""
	@echo "Módulos:"
	@ls -d modules/*/ | wc -l

install: build ## Instala MAI en /Applications
	@echo "📦 Instalando MAI Browser..."
	@# TODO: Crear bundle .app e instalar
	@echo "⚠️  Instalación aún no implementada"

uninstall: ## Desinstala MAI
	@echo "🗑️  Desinstalando MAI Browser..."
	@rm -rf /Applications/MAI.app
	@echo "✅ MAI desinstalado"

.DEFAULT_GOAL := help
