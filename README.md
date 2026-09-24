# SLAP Mobile

Aplicativo de inventário patrimonial **offline-first e distribuído**, feito para substituir o
sistema web SLAP usado no Instituto Federal do Piauí.

O sistema atual depende de um servidor central: os usuários acessam pelo navegador, e sem rede
não há inventário. Aqui cada celular carrega uma cópia completa dos dados, funciona sozinho e
sincroniza direto com os outros aparelhos pela rede local — sem servidor e sem internet.

O levantamento é feito por leitura de código de barras, pela câmera ou por leitor externo, com
retorno sonoro para cada resultado: encontrado, já verificado ou não localizado. Ao final, o
aplicativo separa os patrimônios em três grupos — o que está correto, o que precisa ser alterado
no SUAP e o que não foi localizado — e exporta cada um em XLSX ou CSV.

> **Estado:** a primeira versão, 1.0.0, está em preparação. Antes da publicação vem o
> [teste em campo](docs/teste-em-campo.md) num campus. O que ela faz e o que ainda não faz está nas
> [notas da versão](docs/notas/v1.0.0.md).

## Permissões

Apenas **câmera**, para ler códigos de barras e o QR de pareamento, e **acesso à rede local**,
para os aparelhos se encontrarem e sincronizarem.

Sem localização, sem armazenamento, sem contas, sem anúncios, sem telemetria própria. Os dados do
inventário só saem do aparelho para outro aparelho do mesmo inventário, na mesma rede local e
cifrados. A exceção: no Android, a biblioteca do Google que lê os códigos (ML Kit) envia ao Google
diagnósticos de funcionamento dela — nunca as imagens nem os códigos lidos.

Detalhes na [política de privacidade](https://guilhermefeitosa66.github.io/slap-mobile/privacidade/)
([fonte](docs/privacidade.md)).

## Instalação

Baixe o APK da [versão mais recente](https://github.com/guilhermefeitosa66/slap-mobile/releases/latest)
— `arm64-v8a` serve para praticamente todo celular dos últimos anos — e siga o
[passo a passo de instalação](docs/instalacao.md): como o APK não vem da Play Store, o Android pede
para autorizar a instalação de fonte desconhecida. Precisa de Android 7.0 ou mais novo.

Para atualizar, instale a versão nova por cima. **Não desinstale:** desinstalar apaga o que ainda
não foi sincronizado.

### A partir do código

Com o Flutter na versão do CI e o Android SDK — `make verificar` confere os dois:

```bash
make apk        # gera build/app/outputs/flutter-apk/app-release.apk
make instalar   # gera e instala por cima no celular conectado, sem apagar dados
```

Sem a chave de release (`android/key.properties`), esse APK sai assinado com a chave de debug: serve
para testar, mas não atualiza uma versão publicada. A release assinada segue
[docs/release.md](docs/release.md) e [docs/assinatura.md](docs/assinatura.md).

## Desenvolvimento

`make` lista as tarefas:

| Tarefa | O que faz |
|---|---|
| `make dependencias` | instala os pacotes (`flutter pub get`) |
| `make verificar` | confere o Flutter (a versão do CI), o Android SDK e o Java, os pacotes do `pubspec.lock` e se há aparelho conectado |
| `make desatualizadas` | lista os pacotes que têm versão mais nova |
| `make rodar` | roda em modo de desenvolvimento (debug, com hot reload) no aparelho ou emulador |
| `make apk` | gera o APK de uso, que instala em qualquer Android 7.0+ |
| `make instalar` | gera o APK e instala por cima no aparelho, mantendo os dados |
| `make testar` | formatação, análise e testes, como no CI |
| `make limpar` | apaga o que os builds geraram |

Não há ambientes de desenvolvimento, homologação e produção: o aplicativo funciona sozinho no
aparelho, e o APK instalado é a versão de uso. Com mais de um aparelho conectado, escolha com
`DISPOSITIVO=<id>` (os ids saem em `flutter devices`); opções a mais para o Flutter vão em `ARGS`,
por exemplo `make apk ARGS=--dart-define=SLAP_DESCOBERTA=beacon`.

**`make rodar` num celular com dados reais:** se a instalação falhar — o SLAP do aparelho foi
assinado com outra chave, ou é de versão mais nova —, o Flutter desinstala e instala de novo, e
desinstalar apaga os inventários. `make instalar` nunca desinstala.

## Licença

[Apache-2.0](LICENSE).
