#!/usr/bin/env bash
# Instala o APK por cima do que está no aparelho, mantendo os dados. Uso: make
# instalar (ou tool/instalar_apk.sh <apk> [dispositivo]).
#
# Por adb, e não por `flutter install`: ele desinstala a versão anterior antes
# de instalar, e desinstalar apaga os inventários ainda não sincronizados.

set -euo pipefail

apk="${1:?informe o caminho do APK}"
dispositivo="${2:-}"

falhar() {
  printf 'Erro: %s\n' "$1" >&2
  exit 1
}

[[ -f "$apk" ]] || falhar "$apk não existe. Gere antes com make apk."

adb="$(command -v adb || true)"
if [[ -z "$adb" ]]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [[ -n "$sdk" && -x "$sdk/platform-tools/adb" ]]; then
      adb="$sdk/platform-tools/adb"
      break
    fi
  done
fi
[[ -n "$adb" ]] ||
  falhar "adb não encontrado. Ele vem no Android SDK, em platform-tools; defina ANDROID_HOME ou ponha o adb no PATH."

# Array vazio com set -u quebra no bash 3.2 do macOS; daí o ${...+...}.
opcoes=()
[[ -n "$dispositivo" ]] && opcoes=(-s "$dispositivo")

if ! "$adb" ${opcoes[@]+"${opcoes[@]}"} install -r "$apk"; then
  cat >&2 <<'FIM'

A instalação por cima falhou. Se o erro é INSTALL_FAILED_UPDATE_INCOMPATIBLE, o
SLAP do aparelho foi assinado com outra chave; se é INSTALL_FAILED_VERSION_DOWNGRADE,
ele é de versão mais nova. Não desinstale sem antes sincronizar com outro
aparelho e exportar uma cópia (Ajustes → Exportar cópia): desinstalar apaga os
inventários. Ver docs/instalacao.md.
FIM
  exit 1
fi
