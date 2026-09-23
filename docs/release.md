# Processo de release

Uma release sai de um commit da `main` com o CI verde, é gerada e assinada **na máquina de quem
guarda a chave** e é publicada no GitHub (APKs) e na Play Store (App Bundle). O CI nunca assina:
a chave não sai daquela máquina.

## Antes da primeira vez

- Chave de release gerada e com cópias guardadas — [assinatura.md](assinatura.md).
- Flutter na versão do CI (`.github/workflows/ci.yml`) e o Android SDK, com `ANDROID_HOME`
  definido: o script usa o `apksigner` dele para conferir a assinatura.

## Passo a passo

1. **Versão.** Em `pubspec.yaml`, `version: X.Y.Z+N`. `X.Y.Z` é o nome que as pessoas veem; `N` é
   o código da versão, que **só cresce** — o Android recusa instalar um código menor por cima de
   um maior. A mudança entra na `main` por PR, como qualquer outra.

2. **Gerar.** Com a `main` atualizada e sem mudanças locais:

   ```bash
   tool/gerar_release.sh
   ```

   O script recusa rodar sem `android/key.properties`, com mudanças não commitadas ou se a tag
   da versão já apontar para outro commit. Ele gera, em `build/release/vX.Y.Z/`:

   | Arquivo | Para quê |
   |---|---|
   | `slap-X.Y.Z-arm64-v8a.apk` | praticamente todo celular dos últimos anos |
   | `slap-X.Y.Z-armeabi-v7a.apk` | celulares antigos, de 32 bits |
   | `slap-X.Y.Z-x86_64.apk` | emuladores e alguns Chromebooks |
   | `slap-X.Y.Z.aab` | envio à Play Store |
   | `SHA256SUMS.txt` | somas para quem baixa conferir o arquivo |

   E confere a assinatura de cada APK: nenhum com a chave de debug, todos com o mesmo
   certificado. A impressão digital impressa no fim tem de ser a anotada em
   [assinatura.md](assinatura.md#onde-ela-está-e-quem-tem-acesso).

3. **Testar num aparelho que já tem a versão anterior**, instalando por cima:

   ```bash
   adb install -r build/release/vX.Y.Z/slap-X.Y.Z-arm64-v8a.apk
   ```

   Se instalar sem desinstalar, a assinatura é a mesma e os dados ficaram. Depois, o mínimo:
   abrir um inventário existente, ler um código, sincronizar com um segundo aparelho.

4. **Marcar o commit:**

   ```bash
   git tag -a vX.Y.Z -m "SLAP X.Y.Z" && git push origin vX.Y.Z
   ```

5. **Release no GitHub**, a partir da tag: anexar os três APKs e o `SHA256SUMS.txt`, com as notas
   da versão em português (o que o aplicativo faz, o que mudou, o que ainda não faz), a impressão
   digital do certificado e o link para a instalação fora da loja no README.

6. **Play Store:** enviar o `.aab` primeiro para o teste interno e, depois de conferido, para
   produção.

## Se der errado depois de publicado

Não se apaga uma versão publicada para trocar o arquivo: quem já baixou fica com o anterior, e
duas versões diferentes com o mesmo número confundem qualquer relato de problema. Corrige-se com a
versão seguinte (`X.Y.Z+1`, código `N+1`).
