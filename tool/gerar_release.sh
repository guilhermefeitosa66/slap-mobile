#!/usr/bin/env bash
# Gera os arquivos de uma release assinada: um APK por arquitetura, o App
# Bundle para a Play Store e as somas SHA-256, em build/release/v<versão>/.
#
# Roda só na máquina de quem guarda a chave — nunca no CI. Recusa gerar com a
# chave de debug, com mudanças não commitadas, ou com uma tag da versão que
# aponte para outro commit. Ver docs/release.md.

set -euo pipefail

falhar() {
  printf 'Erro: %s\n' "$1" >&2
  exit 1
}

aviso() {
  printf 'Aviso: %s\n' "$1" >&2
}

if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  falhar "a release é gerada e assinada localmente, não no CI."
fi

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$raiz"

[[ -f android/key.properties ]] ||
  falhar "android/key.properties não encontrado: o build sairia com a chave de debug. Ver docs/assinatura.md."

linha="$(grep -E '^version:' pubspec.yaml || true)"
[[ "$linha" =~ ^version:\ *([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\ *$ ]] ||
  falhar "a versão do pubspec.yaml precisa estar no formato X.Y.Z+N."
versao="${BASH_REMATCH[1]}"
codigo="${BASH_REMATCH[2]}"
tag="v$versao"

[[ -z "$(git status --porcelain)" ]] ||
  falhar "há mudanças não commitadas. A release sai de um commit, para poder ser refeita."

commit="$(git rev-parse HEAD)"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  [[ "$(git rev-list -n 1 "$tag")" == "$commit" ]] ||
    falhar "a tag $tag já existe e aponta para outro commit. Aumente a versão no pubspec.yaml."
fi

printf 'Release %s (código %s), commit %s\n\n' "$versao" "$codigo" "${commit:0:12}"

flutter build apk --release --split-per-abi
flutter build appbundle --release

destino="build/release/$tag"
rm -rf "$destino"
mkdir -p "$destino"
# Se algo falhar daqui em diante, não fica pasta de release pela metade — nem
# APK com assinatura errada com cara de pronto.
concluido=""
trap '[[ -n "$concluido" ]] || rm -rf "$destino"' EXIT

apks=()
for origem in build/app/outputs/flutter-apk/app-*-release.apk; do
  [[ -e "$origem" ]] || falhar "o build não gerou APKs em build/app/outputs/flutter-apk/."
  abi="${origem#build/app/outputs/flutter-apk/app-}"
  abi="${abi%-release.apk}"
  cp "$origem" "$destino/slap-$versao-$abi.apk"
  apks+=("$destino/slap-$versao-$abi.apk")
done
bundle="build/app/outputs/bundle/release/app-release.aab"
[[ -f "$bundle" ]] || falhar "o build não gerou $bundle."
cp "$bundle" "$destino/slap-$versao.aab"

# Conferência da assinatura: nenhuma chave de debug, e o mesmo certificado em
# todos os APKs. A impressão digital é pública; é ela que se compara com a
# anotada em docs/assinatura.md.
apksigner=""
for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
  [[ -n "$sdk" && -d "$sdk/build-tools" ]] || continue
  apksigner="$(find "$sdk/build-tools" -maxdepth 2 -name apksigner -type f 2>/dev/null |
    sort -V | tail -n 1)"
  [[ -n "$apksigner" ]] && break
done

impressao=""
if [[ -n "$apksigner" ]]; then
  for apk in "${apks[@]}"; do
    certificado="$("$apksigner" verify --print-certs "$apk")" ||
      falhar "$apk não passou na verificação de assinatura."
    grep -q 'CN=Android Debug' <<<"$certificado" &&
      falhar "$apk saiu assinado com a chave de debug."
    digest="$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' <<<"$certificado")"
    [[ -n "$digest" ]] || falhar "não consegui ler o certificado de $apk."
    [[ -z "$impressao" || "$impressao" == "$digest" ]] ||
      falhar "os APKs saíram com certificados diferentes."
    impressao="$digest"
  done
else
  aviso "apksigner não encontrado (defina ANDROID_HOME). A assinatura dos APKs não foi conferida."
fi

(
  cd "$destino"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- *.apk *.aab >SHA256SUMS.txt
  else
    shasum -a 256 -- *.apk *.aab >SHA256SUMS.txt
  fi
)

concluido=1

printf '\nArquivos em %s:\n' "$destino"
for arquivo in "$destino"/*; do
  printf '  %s\n' "${arquivo##*/}"
done
if [[ -n "$impressao" ]]; then
  printf '\nCertificado (SHA-256): %s\n' "$impressao"
  printf 'Confira com a impressão digital anotada em docs/assinatura.md.\n'
fi
if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  printf '\nDepois de testar os APKs, marque o commit:\n  git tag -a %s -m "SLAP %s" && git push origin %s\n' \
    "$tag" "$versao" "$tag"
fi
