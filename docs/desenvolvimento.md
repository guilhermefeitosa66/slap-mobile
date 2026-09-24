# Desenvolvimento

O que o README resume, com o detalhe que não cabe lá. As regras de projeto que valem para
qualquer alteração estão em [`CLAUDE.md`](../CLAUDE.md); a arquitetura, em
[`02-arquitetura.md`](02-arquitetura.md).

## Ambiente

Flutter na versão do CI e o Android SDK — `make verificar` confere os dois, mais o Java, os
pacotes do `pubspec.lock` e se há aparelho conectado. Não há ambientes de desenvolvimento,
homologação e produção: o aplicativo funciona sozinho no aparelho, e o APK instalado é a versão de
uso.

Com mais de um aparelho conectado, escolha com `DISPOSITIVO=<id>` (os ids saem em
`flutter devices`); opções a mais para o Flutter vão em `ARGS`, por exemplo
`make apk ARGS=--dart-define=SLAP_DESCOBERTA=beacon`.

`flutter analyze` pode falhar em máquinas Linux com "Too many open files": o analisador vigia o
pub cache por inotify e estoura `fs.inotify.max_user_instances`, que vem em 128 por padrão. Ou
suba o limite (`sudo sysctl -w fs.inotify.max_user_instances=1024`, como o CI faz), ou use
`flutter test` como verificação de tipos — ele compila o projeto inteiro.

## Rodar e instalar

```bash
make rodar      # debug, com hot reload, no aparelho ou emulador
make apk        # gera build/app/outputs/flutter-apk/app-release.apk
make instalar   # gera e instala por cima no celular conectado, sem apagar dados
```

**`make rodar` num celular com dados reais:** se a instalação falhar — o SLAP do aparelho foi
assinado com outra chave, ou é de versão mais nova —, o Flutter desinstala e instala de novo, e
desinstalar apaga os inventários. `make instalar` nunca desinstala: ele usa o `adb` diretamente.

Sem a chave de release (`android/key.properties`), o APK sai assinado com a chave de debug: serve
para testar, mas não atualiza uma versão publicada. A release assinada segue
[`release.md`](release.md) e [`assinatura.md`](assinatura.md).

## Permissões do aplicativo

Apenas **câmera**, para ler códigos de barras e o QR code de entrada num inventário, e **acesso à
rede local**, para os aparelhos se encontrarem e sincronizarem. Sem localização, sem armazenamento,
sem contas, sem anúncios, sem telemetria própria. A exceção, no Android, é a biblioteca do Google
que lê os códigos (ML Kit), que envia ao Google diagnósticos de funcionamento dela — nunca as
imagens nem os códigos lidos. O detalhe está na [política de privacidade](privacidade.md).

## Testes

```bash
flutter test                                       # suíte completa
flutter test test/data/sincronizacao_test.dart     # um arquivo
flutter test --plain-name 'detecta conflito'       # um teste pelo nome
```

Os testes que importam são os de `test/data/sincronizacao_test.dart` (convergência entre réplicas,
propagação transitiva, concorrência versus atualização) e `test/features/sync_http_test.dart`
(transporte sobre sockets reais, assinatura, pacote inicial). Ao mexer em relógio híbrido, version
vector, contexto causal ou materialização, rode essa suíte antes de qualquer outra coisa.

## Capturas de tela

As imagens do README e do site estão em [`imagens/`](imagens/), com o procedimento em
[`imagens/README.md`](imagens/README.md). As capturas da listagem na loja, com dados fictícios,
são geradas por teste golden:

```bash
flutter test --run-skipped --tags capturas --update-goldens
```

## Site

`tool/gerar_site.py` gera o site do GitHub Pages a partir do que está versionado: os textos da
página inicial, `privacidade.md`, as capturas de `imagens/` e a logomarca de `marca/`. O workflow
`Site` publica a cada alteração desses arquivos na `main`.

```bash
pip install markdown
make site                             # gera _site/; abra _site/index.html no navegador
```
