# Tarefas do dia a dia. `make` sem argumento lista todas.
#
# Não há ambientes (desenvolvimento, homologação, produção): o aplicativo
# funciona sozinho no aparelho, sem servidor. O APK instalado é a versão de uso.
#
# Variáveis:
#   DISPOSITIVO=<id>  aparelho a usar quando há mais de um (ids: flutter devices)
#   ARGS="..."        opções a mais para o Flutter em rodar e apk, por exemplo
#                     ARGS=--dart-define=SLAP_DESCOBERTA=beacon

FLUTTER ?= flutter
# O `dart` avulso pode existir no PATH e mesmo assim não rodar (um shim do asdf
# sem versão escolhida, por exemplo). Quando não roda, usa-se o que vem junto
# com o Flutter, que sempre existe.
DART ?= $(shell if dart --version >/dev/null 2>&1; then echo dart; \
	else echo "$$(dirname "$$(command -v flutter)")/dart"; fi)
DISPOSITIVO ?=
ARGS ?=

APK := build/app/outputs/flutter-apk/app-release.apk

.DEFAULT_GOAL := ajuda
.PHONY: ajuda dependencias verificar desatualizadas rodar apk instalar site testar limpar

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
