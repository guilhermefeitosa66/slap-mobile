# Tarefas do dia a dia. `make` sem argumento lista todas.
#
# Não há ambientes (desenvolvimento, homologação, produção): o aplicativo
# funciona sozinho no aparelho, sem servidor. O APK instalado é a versão de uso.
#
# Variáveis:
#   DISPOSITIVO=<id>  aparelho a usar quando há mais de um (ids: flutter devices)
#   ARGS="..."        opções a mais para o Flutter em rodar e apk, por exemplo
#                     ARGS=--dart-define=SLAP_DESCOBERTA=beacon
#   AVD=<nome>        emulador a abrir em `emulador` (nomes: make emuladores)
#   CAMERA=<webcam>   câmera traseira do emulador (nomes: make cameras)
#   QR=<arquivo.png>  imagem que a câmera traseira mostra, em vez de webcam

FLUTTER ?= flutter
# O `dart` avulso pode existir no PATH e mesmo assim não rodar (um shim do asdf
# sem versão escolhida, por exemplo). Quando não roda, usa-se o que vem junto
# com o Flutter, que sempre existe.
DART ?= $(shell if dart --version >/dev/null 2>&1; then echo dart; \
	else echo "$$(dirname "$$(command -v flutter)")/dart"; fi)
DISPOSITIVO ?=
ARGS ?=

APK := build/app/outputs/flutter-apk/app-release.apk

# ------------------------------------------------------------- emuladores ---
#
# Testar a leitura do QR code entre dois emuladores exige uma câmera de
# verdade do lado que lê: a cena sintética do emulador não mostra o código do
# outro. O caminho é uma câmera virtual — o OBS compartilhando a janela do
# emulador que exibe o QR — ligada ao emulador que lê.
#
#   make cameras                        lista as câmeras (a do OBS aparece
#                                       quando a câmera virtual está ligada)
#   make emuladores                     lista os AVDs
#   make emulador AVD=Large_Phone       abre um emulador
#   make emulador AVD=Medium_Phone CAMERA=webcam2
#                                       abre com a câmera do OBS na traseira
#   make emulador AVD=Medium_Phone QR=/tmp/qr.png
#                                       a traseira mostra a imagem do arquivo
#
# QR= é o caminho curto para testar a leitura do código: o emulador renderiza
# um arquivo de imagem como se fosse a câmera. Dispensa câmera virtual, e não
# esbarra no formato que ela anuncia — a do OBS sai em 2560x1600, tamanho que
# a ponte de webcam do emulador não negocia, e as duas pontas falham ao abrir
# a câmera. Recorte o QR do outro aparelho e centralize num quadro 1280x720.
#
# A frontal vai para a cena sintética sempre que CAMERA é informada. O AVD
# costuma trazer as duas apontando para a webcam integrada, que é justamente a
# fonte que o OBS está capturando: o emulador não consegue abri-la, expõe uma
# câmera só, e o aplicativo de câmera do Android quebra com
# `ArrayIndexOutOfBoundsException: length=1; index=1` ao procurar a frontal.
#
# O Android Studio instalado por Flatpak guarda os AVDs dentro do sandbox, e
# não em ~/.android/avd, onde o emulador avulso procura. AVD_HOME aponta para
# lá quando a pasta existe.
EMULADOR := $(HOME)/Android/Sdk/emulator/emulator
AVD_FLATPAK := $(HOME)/.var/app/com.google.AndroidStudio/config/.android/avd
AVD_HOME ?= $(shell if [ -d "$(AVD_FLATPAK)" ] && [ -n "$$(ls -A $(AVD_FLATPAK) 2>/dev/null)" ]; \
	then echo "$(AVD_FLATPAK)"; else echo "$(HOME)/.android/avd"; fi)
AVD ?=
CAMERA ?=
QR ?=
# A traseira: o arquivo de imagem tem precedência sobre a webcam.
TRASEIRA := $(if $(QR),imagefile:$(QR),$(CAMERA))
CAMERA_FRONTAL ?= $(if $(TRASEIRA),emulated)

# O caminho de GPU padrão estoura com SIGSEGV nesta máquina, durante o boot do
# convidado. Sem Vulkan, a aceleração por hardware continua e o emulador sobe.
# Se ainda assim cair, GPU=swiftshader_indirect desenha por software.
GPU ?= host -feature -Vulkan

.DEFAULT_GOAL := ajuda
.PHONY: ajuda dependencias verificar desatualizadas rodar apk instalar site \
	testar limpar emuladores cameras emulador

ajuda: ## Lista as tarefas
	@echo "Uso: make <tarefa>"
	@echo
	@awk -F ':.*## ' '/^[a-z]+:.*## / { printf "  %-15s %s\n", $$1, $$2 }' $(firstword $(MAKEFILE_LIST))
	@echo
	@echo "Mais de um aparelho conectado: DISPOSITIVO=<id> (ids em: flutter devices)."

dependencias: ## Instala os pacotes do pubspec (flutter pub get)
	$(FLUTTER) pub get

verificar: ## Confere Flutter, Android SDK, Java, pacotes e aparelhos
	@FLUTTER="$(FLUTTER)" tool/verificar_ambiente.sh

desatualizadas: ## Lista os pacotes que têm versão mais nova
	$(FLUTTER) pub outdated

# Se a instalação falhar — o SLAP do aparelho foi assinado com outra chave, ou
# é de versão mais nova —, o `flutter run` desinstala e instala de novo, e
# desinstalar apaga os inventários. Use num aparelho de teste.
rodar: ## Roda em modo de desenvolvimento (debug, com hot reload)
	$(FLUTTER) run $(if $(DISPOSITIVO),-d $(DISPOSITIVO)) $(ARGS)

apk: ## Gera o APK de uso, que instala em qualquer Android 7.0+
	$(FLUTTER) build apk --release $(ARGS)
	@echo
	@echo "APK: $(APK)"
	@if [ ! -f android/key.properties ]; then \
	  echo "Atenção: assinado com a chave de debug, porque não há android/key.properties."; \
	  echo "Serve para testar, mas não atualiza uma versão publicada (docs/assinatura.md)."; \
	fi

# Por adb, e não por `flutter install`, que desinstala a versão anterior antes
# de instalar e apaga os inventários.
instalar: apk ## Gera o APK e instala por cima no aparelho, sem apagar dados
	@tool/instalar_apk.sh "$(APK)" "$(DISPOSITIVO)"

site: ## Gera o site do GitHub Pages em _site (requer o pacote markdown)
	python3 tool/gerar_site.py _site
	@echo
	@echo "Site: _site/index.html"

# `dart analyze` no lugar de `flutter analyze`: o segundo vigia o pub cache por
# inotify e estoura o limite padrão do Linux. O CI sobe o limite e roda o
# `flutter analyze`; aqui o resultado é o mesmo sem precisar de sudo.
testar: ## Formatação, análise e testes, como no CI
	$(DART) format --output=none --set-exit-if-changed lib test
	$(DART) analyze lib test
	$(FLUTTER) test

limpar: ## Apaga o que os builds geraram (flutter clean)
	$(FLUTTER) clean

emuladores: ## Lista os emuladores disponíveis (AVDs)
	@ANDROID_AVD_HOME="$(AVD_HOME)" $(EMULADOR) -list-avds

cameras: ## Lista as câmeras que o emulador pode usar (inclui a do OBS)
	@$(EMULADOR) -webcam-list

# Em segundo plano e sem terminal preso: o emulador fica aberto depois que o
# make termina, que é o que se quer ao abrir dois para testar a troca de dados.
emulador: ## Abre um emulador: AVD=<nome> [CAMERA=<webcam>]
	@if [ -z "$(AVD)" ]; then \
	  echo "Informe o AVD: make emulador AVD=<nome> (nomes: make emuladores)"; \
	  exit 1; \
	fi
	@echo "Abrindo $(AVD)$(if $(QR), mostrando $(QR) na câmera traseira)$(if $(CAMERA), com a câmera $(CAMERA) na traseira)…"
	@ANDROID_AVD_HOME="$(AVD_HOME)" nohup $(EMULADOR) @$(AVD) \
	  -gpu $(GPU) -no-boot-anim \
	  $(if $(TRASEIRA),-camera-back $(TRASEIRA)) \
	  $(if $(CAMERA_FRONTAL),-camera-front $(CAMERA_FRONTAL)) \
	  > /tmp/emulador-$(AVD).log 2>&1 & \
	  echo "Registro em /tmp/emulador-$(AVD).log"
