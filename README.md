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

> **Estado:** em desenvolvimento, sem release publicada.

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

Ainda não há APK publicado. Quando houver, estará em
[Releases](https://github.com/guilhermefeitosa66/slap-mobile/releases).

Para gerar o APK a partir do código:

```bash
flutter build apk --release --split-per-abi
```

Os arquivos saem em `build/app/outputs/flutter-apk/`. Instale o que corresponde ao processador do
aparelho — `arm64-v8a` cobre praticamente todos os celulares dos últimos anos.

Sem a chave de release (`android/key.properties`), esse APK sai assinado com a chave de debug:
serve para testar, mas não atualiza uma versão publicada. A release assinada segue
[docs/release.md](docs/release.md) e [docs/assinatura.md](docs/assinatura.md).

Como o APK não vem da Play Store, o Android pede autorização para instalar de fonte desconhecida.
A permissão é concedida ao aplicativo usado para abrir o arquivo, em
**Configurações → Aplicativos → Acesso especial → Instalar apps desconhecidos**.

## Licença

[Apache-2.0](LICENSE).
