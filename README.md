# SLAP Mobile

Aplicativo de inventário patrimonial **offline-first e distribuído**, feito para substituir o
sistema web SLAP usado no Instituto Federal do Piauí.

O sistema atual depende de um servidor central: os usuários acessam pelo navegador, e sem rede
não há inventário. Aqui cada celular carrega uma cópia completa dos dados, funciona sozinho e
sincroniza direto com os outros aparelhos pela rede local — sem servidor e sem internet.

> **Estado:** funcional ponta a ponta e compilando para Android, com 70 testes
> automatizados. **Ainda não foi testado com vários celulares reais numa rede de
> campus** — é o próximo passo antes de qualquer release.

---

## O que ele faz

- Cria processos de inventário e importa os patrimônios de planilhas exportadas do SUAP
  (**XLSX** e **CSV**), reconhecendo as colunas pelo nome em vez da posição.
- Permite ignorar Elementos de Despesa que não entram no inventário, como material bibliográfico.
- Faz o levantamento inteiro pelo celular: leitura por **câmera** (contínua, em lote) ou por
  **leitor de código de barras externo**, com busca por tombo ou por código de barras.
- Aplica automaticamente sala, estado de conservação, situação de uso e responsável às leituras
  seguintes — uma leitura não exige nenhum toque na tela.
- Dá **feedback sonoro distinto** para sucesso, item já verificado e código não localizado, para
  que o levantamento ocorra sem olhar para a tela.
- Identifica divergências de sala e responsável, itens sem alteração e itens não localizados.
- **Sincroniza entre celulares pela rede local**, detecta alterações conflitantes e apresenta os
  conflitos para resolução.
- Exporta os relatórios em XLSX e CSV a partir de **qualquer** aparelho sincronizado.

Tudo funciona sem internet. A rede local é necessária apenas para sincronizar.

## Permissões

Apenas duas: **câmera**, para ler códigos de barras e o QR de pareamento, e **acesso à rede
local**, para os aparelhos se encontrarem e sincronizarem.

Sem localização, sem armazenamento, sem contas, sem telemetria. Nenhum dado sai do aparelho a
não ser para outro aparelho do mesmo inventário, na mesma rede local.

## Como funciona a sincronização

Não existe servidor, nem aparelho designado como principal. Cada celular é ao mesmo tempo
cliente e servidor.

Toda alteração vira uma operação imutável num log local. Sincronizar é trocar as operações que
faltam de cada lado — nunca o inventário inteiro. As réplicas convergem sozinhas, e quando duas
pessoas alteram o mesmo campo do mesmo patrimônio sem saber uma da outra, o app detecta a
concorrência de verdade e apresenta o conflito, em vez de escolher em silêncio.

O desenho completo está em [`docs/02-arquitetura.md`](docs/02-arquitetura.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/01-analise-slap.md`](docs/01-analise-slap.md) | Análise do sistema atual: modelo de dados, regras de negócio, valores de domínio e os problemas que este app corrige |
| [`docs/02-arquitetura.md`](docs/02-arquitetura.md) | Escolha da stack, modelo de dados, protocolo de sincronização, detecção de conflitos, permissões |

## O que já funciona e o que falta

| Etapa | Estado |
|---|---|
| Análise do SLAP e arquitetura | pronto — ver `docs/` |
| Banco local, identidade, inventários | pronto |
| Importação XLSX/CSV, mapeamento de colunas, filtro de ED | pronto |
| Levantamento: leitor externo, câmera contínua, sons, configuração pegajosa | pronto |
| Divergências, classificação nos três grupos, progresso | pronto |
| Sincronização P2P, descoberta, conflitos, resolução | pronto |
| Relatórios XLSX e CSV | pronto |
| **Teste em campo com vários celulares** | **pendente** |
| Ícone próprio do aplicativo | pendente |
| Cifrar o corpo da sincronização | pendente — ver limitação em `docs/02-arquitetura.md` |

O que existe está coberto por testes automatizados, incluindo a convergência
entre três réplicas e a sincronização sobre sockets HTTP reais. O que nenhum
teste automatizado cobre é o comportamento do mDNS e do multicast na rede real
de um campus — é onde a descoberta costuma falhar, e por isso existe o beacon
UDP como segunda via.

## Desenvolvimento

Requer Flutter 3.38 ou superior.

```bash
flutter pub get
flutter run
```

Testes:

```bash
flutter test
```

Gerar os APKs de release, um por arquitetura:

```bash
flutter build apk --release --split-per-abi
```

Os três sons de retorno são sintetizados por `tool/gerar_sons.py` e versionados
em `assets/sons/`. Só é preciso rodar o script para alterá-los.

### Nota sobre o analisador

`flutter analyze` pode falhar com `Too many open files` em Linux: o analisador
vigia o pub cache inteiro e estoura o limite de instâncias do inotify, que vem
baixo por padrão. `flutter test` compila o projeto e serve como verificação de
tipos enquanto isso.

## Licença

[Apache-2.0](LICENSE).

A GPL foi considerada, mas é incompatível com os Termos de Serviço da App Store da Apple, e o
projeto pretende ser publicado nas duas lojas. A Apache-2.0 mantém o código aberto e ainda traz
concessão explícita de patentes.
