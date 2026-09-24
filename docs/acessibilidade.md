# Acessibilidade

O levantamento é feito em pé, andando, muitas vezes com uma das mãos ocupada pelo leitor de
código de barras — e por pessoas de todas as idades e visões. As telas foram revistas pelo que o
TalkBack enxerga: a árvore de semântica do Flutter.

## O que está garantido por teste

`test/acessibilidade/auditoria_test.dart` percorre as telas principais — inventários, painel,
levantamento (com histórico), itens, conflitos, relatórios, ajustes, identidade e importação — e
confere, em cada uma:

- **Alvos de toque** de pelo menos 48 dp (`androidTapTargetGuideline`).
- **Rótulo em tudo o que se toca**, inclusive botões só de ícone (`labeledTapTargetGuideline`).
- **Contraste** de 4,5:1 no texto, e 3:1 a partir de 24 px (`textContrastGuideline`), nos temas
  claro e escuro.
- **Fonte do sistema em 200%** sem estourar o layout.

`test/acessibilidade/talkback_test.dart` registra um patrimônio do início ao fim só pela árvore de
semântica, como o TalkBack faria: acha cada elemento pelo que o leitor de tela fala e aciona pela
ação que ele expõe — cartão do inventário, "Levantar", campo "Sala onde você está", "Aplicar e
continuar", a leitura, e depois "Manter" na confirmação.

## Decisões

- **Os três resultados são falados.** Além de som, vibração, ícone, cor e texto, cada leitura é
  anunciada ao leitor de tela, com prioridade, porque a próxima vem logo: "Registrado. MESA DE
  REUNIÃO, tombo 023101.", "Já verificado por Bruno. … Manter ou regravar?", "Não localizado.
  Código 887401." Vale para o campo de leitura e para a câmera.
- **Cada leitura do histórico é um elemento só**: o leitor de tela lê descrição, tombo e resultado
  de uma vez, em vez de três paradas.
- **A faixa de configuração é um botão com a configuração inteira no rótulo** — sala, estado,
  situação, responsável e desde quando vale —, e diz que tocar altera.
- **O contador do levantamento diz de qual sala é o número** ("Sala Biblioteca: 12 de 40
  verificados, mais 2 itens de outras salas"). Sem a sala no rótulo, `12/40` não significa nada
  fora da tela; numa sala que não está na planilha não há fração, e o rótulo explica por quê.
- **O foco volta ao campo de leitura por código** depois de cada leitura. É foco de entrada, que o
  leitor externo usa; o cursor do TalkBack não é arrastado, e o resultado chega pelo anúncio.
- **Barras de progresso têm valor falado** ("Progresso, 60,2%").
- **Números em português** ("1.204", "60,2%"), que é como o leitor de tela os fala certo.
- **Fonte grande não corta conteúdo**: o percentual do painel encolhe para caber ao lado do selo,
  o "desde" da faixa encolhe antes da sala, e a ação de manter todos os conflitos saiu da barra
  superior — com a fonte em 200% ela não cabia ao lado do título.

## Conferir no aparelho

Os testes cobrem a árvore de semântica; o TalkBack de verdade ainda vale uma passada antes de cada
release. Com o TalkBack ligado (*Configurações → Acessibilidade → TalkBack*):

1. Na lista de inventários, deslize até o cartão do inventário: ele deve ser lido inteiro, com o
   progresso. Toque duas vezes.
2. No painel, deslize até "Levantar" e toque duas vezes.
3. Na configuração, o campo "Sala onde você está" deve ser anunciado como campo de edição. Digite
   a sala e acione "Aplicar e continuar".
4. Leia um patrimônio com o leitor externo. O resultado deve ser falado sem mexer no aparelho.
5. Leia o mesmo patrimônio de novo: deve ser falado "Já verificado … Manter ou regravar?". Deslize
   até "Manter" e toque duas vezes.
6. Repita com a fonte do sistema no máximo (*Configurações → Tela → Tamanho da fonte*): nada deve
   ficar cortado.
