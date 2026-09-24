# Logomarca do SLAP Mobile

O símbolo é o próprio ícone do aplicativo: o motivo do código de barras —
cinco barras de ponta arredondada, a quarta mais curta — num quadrado de
cantos arredondados. Não é uma ilustração à parte; é a mesma grade de 24
unidades que `tool/gerar_icones.py` usa para gerar os ícones do Android e do
iOS e que `IconeCodigoBarras` (`lib/app/componentes.dart`) desenha dentro do
app. Aplicativo e marca são a mesma coisa, de propósito.

O nome é "SLAP Mobile" em Archivo SemiBold, a fonte dos títulos do app.

Nada aqui é desenhado à mão: tudo sai de `tool/gerar_marca.py`, e é de lá que
vêm as proporções descritas abaixo.

## Os arquivos

Três composições, em três variantes de cor:

| Composição | Quando usar |
|---|---|
| `simbolo-*` | ícone, favicon, avatar, qualquer lugar apertado ou quadrado |
| `horizontal-*` | cabeçalho de site, README, apresentação, assinatura de rodapé |
| `vertical-*` | espaço estreito e alto, camiseta, adesivo, capa |

| Variante | Tinta | Barras | Fundo | Contraste |
|---|---|---|---|---|
| `-claro` | teal `#0F5C52` | branco | `#F7F6F3` | 7,3:1 e 7,9:1 |
| `-escuro` | teal claro `#8FCFC2` | `#0B2A25` | `#111816` | 10,2:1 e 8,7:1 |
| `-mono` | uma tinta só (preta) | vazadas | transparente | — |

As cores são tokens de `lib/app/tema.dart` (`PaletaClara` e `PaletaEscura`),
não valores escolhidos aqui.

A clara e a escura já trazem o fundo desenhado — é o fundo que dá nome ao
arquivo e é dele que vem o contraste medido. A monocromática é vazada e sem
fundo: as barras deixam passar o que estiver atrás, então ela serve a carimbo,
gravação, documento em preto e branco, fundo de cor qualquer e ao ícone com
tema do Android 13+, que o sistema tinge sozinho.

### Vetor

`{simbolo,horizontal,vertical}-{claro,escuro,mono}.svg` — a arte de origem.
O nome já vem convertido em caminhos, então o arquivo não depende de a
Archivo estar instalada em quem abrir.

### Bitmap

- `horizontal-claro.png` (800 × 243) — **a versão canônica**, a que o README
  e o site apontam. O nome é fixo: não renomear nem trocar por outro tamanho.
- `png/simbolo-{variante}-{24,48,192,512,1024}.png` — quadrado, sangrado.
- `png/{horizontal,vertical}-{variante}-{400,800,1600}.png` — largura em
  pixels; a altura sai da proporção (horizontal 3,29:1, vertical 1,20:1).

Precisa de um tamanho que não está aqui? Use o SVG, ou acrescente o tamanho
em `TAMANHOS_SIMBOLO` / `LARGURAS_COMPOSICAO` e rode o gerador. Não
redimensione um PNG à mão.

## Área de respiro

Em volta da marca fica livre um quarto do lado do símbolo — a mesma medida em
cima, embaixo e dos lados. Nada entra nessa faixa: nem texto, nem borda, nem
outro logotipo, nem o recorte de uma foto.

Nos arquivos horizontais e verticais o respiro **já está incluído**: é a
margem que se vê entre a tinta e a borda da imagem. Basta encostar o arquivo
no que vier ao lado. O `simbolo-*` é a exceção — é ícone, e ícone ocupa o
quadrado inteiro; o respiro dele, quando houver, é responsabilidade de quem
aplica.

## Tamanho mínimo

| Peça | Mínimo | Por quê |
|---|---|---|
| `simbolo-*` | 24 px de lado | abaixo disso as cinco barras viram um borrão |
| `horizontal-*` | 180 px de largura | é onde "Mobile" ainda se lê |
| `vertical-*` | 160 px de largura | o nome é menor aqui do que na horizontal |

Entre 24 e 32 px as barras já se tocam um pouco: é o limite da grade de 24
unidades, em que o traço vale 2 unidades. Abaixo de 24 px, não use o símbolo
— use o nome sozinho, ou nada.

Quando a largura disponível não chegar aos 180 px da horizontal, prefira o
símbolo sozinho a espremer a composição inteira.

## O que não fazer

- **Não recompor.** A distância entre símbolo e nome, o tamanho relativo dos
  dois e o respiro são fixos. Para um arranjo novo, mude os parâmetros em
  `tool/gerar_marca.py` e gere de novo — não mova as peças num editor.
- **Não trocar a fonte** nem redigitar o nome. O nome vem em caminhos, com
  dois ajustes ópticos que a Archivo não traz (o par L-A e o espaço entre as
  palavras); redigitado, sai diferente.
- **Não aplicar efeito.** Sem gradiente, sombra, relevo, brilho ou contorno.
  A marca é chapada.
- **Não recolorir.** Só as três variantes deste diretório. Em especial, as
  barras não mudam de cor por conta própria.
- **Não usar a variante clara sobre fundo escuro** (nem a escura sobre claro):
  para isso existem as duas, e o contraste da tabela é o de cada par.
- **Não distorcer, girar nem inclinar.** A escala é sempre proporcional.
- **Não pôr a marca sobre foto ou textura.** Se for inevitável, use a
  monocromática sobre uma área de cor lisa.
- **Não editar os arquivos deste diretório à mão.** São saída de gerador;
  a próxima rodada apaga a edição.

## Como regenerar

O gerador precisa do Pillow e do fontTools. O fontTools costuma faltar, daí o
ambiente à parte — o `.gitignore` já cobre `.venv*/`:

```bash
python3 -m venv .venv-marca
.venv-marca/bin/pip install pillow fonttools
.venv-marca/bin/python tool/gerar_marca.py
```

Isso reescreve todo este diretório e também `docs/loja/destaque.png`, a
imagem de destaque da Play Store, que é a mesma marca com a frase da listagem.
O ícone do aplicativo continua saindo de `tool/gerar_icones.py`, que só
depende do Pillow; `gerar_marca.py` importa dele a geometria das barras, de
modo que um ajuste no motivo chega aqui sozinho.

A saída é determinística: rodar duas vezes sem mexer em nada dá arquivos
idênticos, e um `git status` limpo é o sinal de que nada saiu do lugar.
