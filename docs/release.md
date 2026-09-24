# Processo de release

Uma release sai de um commit da `main` com o CI verde, é gerada e assinada **na máquina de quem
guarda a chave** e é publicada no GitHub (APKs) e na Play Store (App Bundle). O CI nunca assina:
a chave não sai daquela máquina.

## Antes da primeira vez

- Chave de release gerada e com cópias guardadas — [assinatura.md](assinatura.md).
- Flutter na versão do CI (`.github/workflows/ci.yml`) e o Android SDK, com `ANDROID_HOME`
  definido: o script usa o `apksigner` dele para conferir a assinatura.
- **Desenvolvedor e pacote registrados no Google** — ver abaixo. Sem isso, a partir de
  30 de setembro de 2026 os celulares Android certificados no Brasil não instalam o APK pelo
  caminho normal.

### Verificação de desenvolvedor do Android

O Android passou a exigir que todo aplicativo instalado em aparelho certificado — inclusive fora
da Play Store — seja de um desenvolvedor com identidade registrada no Google. No Brasil a regra vale
a partir de **30 de setembro de 2026**; no resto do mundo, a partir de 2027. Aplicativo de desenvolvedor
não registrado só instala por ADB ou por um caminho avançado, com espera de 24 horas, que não dá
para pedir a quem vai fazer o inventário.

Uma vez só:

1. **Conta.** No [Android Developer Console](https://developer.android.com/developer-verification)
   (ou no Play Console, se o app for para a loja — [listagem](loja/listagem.md)): verificação de
   identidade e taxa única. Para o teste em campo basta a conta de **distribuição limitada**,
   gratuita, que autoriza até 20 aparelhos.
2. **Pacote.** Registrar `io.github.guilhermefeitosa66.slap_mobile` com o certificado **público**
   da chave de release, exportado assim (sem senha no comando: o `keytool` pergunta):

   ```bash
   keytool -exportcert -rfc -keystore ~/.slap-chaves/slap-release.jks \
     -alias "<alias>" -file slap-release.pem
   ```

   O `.pem` é público e pode ser enviado; o `.jks` e a senha não saem da máquina.

Confira os passos atuais na documentação do Google antes: o processo é novo e ainda muda.

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
   | `slap-X.Y.Z.apk` | o arquivo que se baixa: um só, com as duas arquiteturas ARM |
   | `slap-X.Y.Z.aab` | envio à Play Store |
   | `SHA256SUMS.txt` | somas para quem baixa conferir o arquivo |
   | `notas.md` | notas da versão, com a impressão digital preenchida |

   E confere o APK: nem chave de debug, nem x86 dentro, e as duas arquiteturas ARM presentes —
   é isso que o torna o único arquivo a baixar. A impressão digital impressa no fim tem de ser a anotada em
   [assinatura.md](assinatura.md#onde-ela-está-e-quem-tem-acesso).

3. **Testar num aparelho que já tem a versão anterior**, instalando por cima:

   ```bash
   adb install -r build/release/vX.Y.Z/slap-X.Y.Z.apk
   ```

   Se instalar sem desinstalar, a assinatura é a mesma e os dados ficaram. Depois, o mínimo:
   abrir um inventário existente, ler um código, sincronizar com um segundo aparelho.

4. **Marcar o commit:**

   ```bash
   git tag -a vX.Y.Z -m "SLAP X.Y.Z" && git push origin vX.Y.Z
   ```

5. **Release no GitHub**, a partir da tag: o APK, o `SHA256SUMS.txt` e as notas da versão.
   As notas são escritas antes, em `docs/notas/vX.Y.Z.md` — o que o aplicativo faz, o que mudou,
   o que ainda não faz —, no mesmo commit da versão; o script recusa gerar sem elas e grava em
   `build/release/vX.Y.Z/notas.md` a cópia com a impressão digital do certificado preenchida
   (`{{certificado}}`). O fim da saída do script traz o comando `gh release create` pronto.

6. **Play Store:** enviar o `.aab` primeiro para o teste interno e, depois de conferido, para
   produção.

## Se der errado depois de publicado

Não se apaga uma versão publicada para trocar o arquivo: quem já baixou fica com o anterior, e
duas versões diferentes com o mesmo número confundem qualquer relato de problema. Corrige-se com a
versão seguinte (`X.Y.Z+1`, código `N+1`).
