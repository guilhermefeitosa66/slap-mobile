#!/usr/bin/env python3
"""Gera a logomarca do SLAP Mobile: os SVGs e PNGs de docs/marca/ e a imagem
de destaque da Play Store.

O símbolo é o próprio ícone do aplicativo — o motivo do código de barras de
tool/gerar_icones.py, na mesma grade de 24 unidades, com a mesma proporção
dentro do quadrado e o mesmo raio de canto. Sair da mesma geometria mantém
ícone, logomarca e imagem da loja como uma coisa só, e refazer tudo depois de
um ajuste é rodar este script de novo. Se a geometria das barras mudar, muda
num lugar só (gerar_icones.py) e chega aqui sozinha.

Construção, com o lado do símbolo valendo 100 unidades:

    símbolo      quadrado de cantos a 22% do lado; as barras na grade de
                 gerar_icones, centradas, ocupando 73% do lado
    horizontal   nome à direita, a 26 do símbolo (medido até a tinta), com
                 altura de capitular 38 e a caixa das capitulares centrada
                 na altura do símbolo
    vertical     nome centrado abaixo, a 22 do símbolo, altura de capitular 22
    respiro      25 em volta das duas composições — um quarto do símbolo, o
                 mesmo raio do canto arredondado mais uma folga
    nome         "SLAP Mobile" em Archivo SemiBold, a fonte dos títulos do
                 app, com o kerning da própria fonte e dois ajustes ópticos:
                 o par L-A, que a fonte deixa em zero, e o espaço entre as
                 palavras, largo no tamanho de uma logomarca

Variantes de cor, com os tokens de lib/app/tema.dart:

    claro   teal 0F5C52 (PaletaClara.teal) e barras brancas, sobre o fundo
            claro F7F6F3 (PaletaClara.fundo)
    escuro  teal claro 8FCFC2 (PaletaEscura.teal) e barras 0B2A25
            (PaletaEscura.sobreTeal), sobre o fundo escuro 111816
    mono    uma tinta só, preta, com as barras vazadas — carimbo, documento e
            a referência do ícone com tema do Android 13+

As duas primeiras levam o fundo desenhado, porque é o fundo que dá nome ao
arquivo e é dele que vem o contraste medido. A monocromática é vazada e sem
fundo: vai sobre qualquer superfície, com uma tinta só.

O texto vira caminhos (fontTools), então os SVGs não dependem de a fonte
estar instalada em quem os abre. Os PNGs são rasterizados aqui mesmo, da
mesma geometria, com superamostragem e redução, como faz gerar_icones.py.

O que sai:

- docs/marca/{simbolo,horizontal,vertical}-{claro,escuro,mono}.svg
- docs/marca/horizontal-claro.png: a versão canônica, 800 px de largura, a
  que o README e o site usam. O nome é fixo de propósito.
- docs/marca/png/: símbolo em 24, 48, 192, 512 e 1024 px; horizontal e
  vertical em 400, 800 e 1600 px de largura, nas três variantes.
- docs/loja/destaque.png (1024 × 500, opaco): a logomarca horizontal com a
  frase da listagem.

Uso:
    python3 -m venv .venv-marca
    .venv-marca/bin/pip install pillow fonttools
    .venv-marca/bin/python tool/gerar_marca.py

Requer Pillow e fontTools (o fontTools não costuma vir com a distribuição;
daí o ambiente à parte, que o .gitignore cobre em `.venv*/`).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import (
    DecomposingRecordingPen,
    RecordingPen,
    replayRecording,
)
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw

import gerar_icones  # mesma pasta: a geometria do ícone

RAIZ = gerar_icones.RAIZ
FONTES = RAIZ / "assets/fontes"
MARCA = RAIZ / "docs/marca"

Cor = tuple[int, int, int]

# Tokens de lib/app/tema.dart.
TEAL = gerar_icones.TEAL  # PaletaClara.teal
FUNDO_CLARO = (0xF7, 0xF6, 0xF3)  # PaletaClara.fundo
TINTA_SECUNDARIA = (0x55, 0x62, 0x5F)  # PaletaClara.tintaSecundaria
TEAL_ESCURO = (0x8F, 0xCF, 0xC2)  # PaletaEscura.teal
SOBRE_TEAL_ESCURO = (0x0B, 0x2A, 0x25)  # PaletaEscura.sobreTeal
FUNDO_ESCURO = (0x11, 0x18, 0x16)  # PaletaEscura.fundo
BRANCO = gerar_icones.BRANCO
PRETO = (0x00, 0x00, 0x00)


@dataclass(frozen=True)
class Variante:
    nome: str
    tinta: Cor  # o quadrado do símbolo e o nome
    barras: Cor | None  # None: barras vazadas (uma tinta só)
    fundo: Cor | None  # None: fundo transparente


VARIANTES = (
    Variante("claro", TEAL, BRANCO, FUNDO_CLARO),
    Variante("escuro", TEAL_ESCURO, SOBRE_TEAL_ESCURO, FUNDO_ESCURO),
    Variante("mono", PRETO, None, None),
)

# ---------------------------------------------------------------------------
# Geometria
# ---------------------------------------------------------------------------

LADO = 100.0  # lado do símbolo, a unidade de tudo o mais
CANTOS = 0.22  # raio dos cantos em fração do lado, como no ícone do Android


@dataclass(frozen=True)
class Parametros:
    """As relações fixas entre símbolo, nome e respiro.

    Fixá-las aqui é o que faz a marca ser sempre a mesma: quem precisar de um
    tamanho novo roda o script, não redesenha.
    """

    fonte: str = "Archivo-SemiBold.ttf"
    capitular_horizontal: float = 38.0
    espaco_horizontal: float = 26.0
    capitular_vertical: float = 22.0
    espaco_vertical: float = 22.0
    respiro: float = 25.0


PADRAO = Parametros()

# Ajustes ópticos do nome, em milésimos de em, somados ao kerning da fonte.
# A Archivo é uma fonte de texto: o espaçamento dela está calibrado para
# corpo pequeno, e no tamanho da logomarca dois vãos abrem demais.
AJUSTES_OPTICOS = {
    ("L", "A"): -20,  # a fonte não fecha L-A, e o vão destoa dos vizinhos
    ("P", " "): -40,  # o espaço entre as duas palavras, largo em display
}


@dataclass(frozen=True)
class Retangulo:
    x: float
    y: float
    largura: float
    altura: float
    raio: float
    cor: Cor | None  # None: vazado na forma anterior


@dataclass(frozen=True)
class Caminho:
    """Contornos gravados por um RecordingPen, nas unidades da composição."""

    contornos: list
    cor: Cor


@dataclass
class Composicao:
    largura: float
    altura: float
    formas: list = field(default_factory=list)
    fundo: Cor | None = None


def formas_simbolo(variante: Variante, x: float = 0.0, y: float = 0.0) -> list:
    """O símbolo com o canto superior esquerdo em (x, y) e lado LADO."""
    formas = [Retangulo(x, y, LADO, LADO, LADO * CANTOS, variante.tinta)]
    unidade = LADO * gerar_icones.ESCALA_DA_GRADE / 24
    # Centro da grade: meio das barras em x (11) e em y (12).
    centro_x, centro_y = x + LADO / 2, y + LADO / 2
    for coluna, fim in gerar_icones.BARRAS:
        x0 = centro_x + (coluna - 11) * unidade
        y0 = centro_y + (gerar_icones.TOPO - 12) * unidade
        y1 = centro_y + (fim - 12) * unidade
        formas.append(
            Retangulo(
                x0 - unidade,
                y0 - unidade,
                2 * unidade,
                y1 - y0 + 2 * unidade,
                unidade,  # traço de 2 unidades, ponta redonda
                variante.barras,
            )
        )
    return formas


# ---------------------------------------------------------------------------
# Texto como caminhos
# ---------------------------------------------------------------------------


class Fonte:
    """Uma fonte TrueType: glifos, avanços, kerning (GPOS) e capitular."""

    _cache: dict[str, Fonte] = {}

    def __init__(self, arquivo: str):
        self.ttf = TTFont(FONTES / arquivo)
        self.cmap = self.ttf.getBestCmap()
        self.glifos = self.ttf.getGlyphSet()
        self.metricas = self.ttf["hmtx"].metrics
        self.upem = self.ttf["head"].unitsPerEm
        self.capitular = self.ttf["OS/2"].sCapHeight
        self._kern = self._subtabelas_kern()
        self._contornos: dict[str, list] = {}

    @classmethod
    def abrir(cls, arquivo: str) -> Fonte:
        if arquivo not in cls._cache:
            cls._cache[arquivo] = cls(arquivo)
        return cls._cache[arquivo]

    def contornos(self, glifo: str) -> list:
        """Os contornos do glifo, já sem componentes.

        Acentuados são glifos compostos, e quem só recebe contornos (o cálculo
        de limites e o rasterizador) não sabe resolver componente; decompor
        aqui resolve de uma vez.
        """
        if glifo not in self._contornos:
            pena = DecomposingRecordingPen(self.glifos)
            self.glifos[glifo].draw(pena)
            self._contornos[glifo] = pena.value
        return self._contornos[glifo]

    def _subtabelas_kern(self) -> list:
        if "GPOS" not in self.ttf:
            return []
        gpos = self.ttf["GPOS"].table
        indices: list[int] = []
        for registro in gpos.FeatureList.FeatureRecord:
            if registro.FeatureTag == "kern":
                for i in registro.Feature.LookupListIndex:
                    if i not in indices:
                        indices.append(i)
        subtabelas = []
        for i in indices:
            for sub in gpos.LookupList.Lookup[i].SubTable:
                sub = getattr(sub, "ExtSubTable", sub)
                if sub.LookupType == 2:
                    subtabelas.append(sub)
        return subtabelas

    def kern(self, primeiro: str, segundo: str) -> int:
        """Ajuste de avanço do par, em unidades da fonte (só o eixo x)."""
        for sub in self._kern:
            cobertura = sub.Coverage.glyphs
            if primeiro not in cobertura:
                continue
            if sub.Format == 1:
                conjunto = sub.PairSet[cobertura.index(primeiro)]
                for par in conjunto.PairValueRecord:
                    if par.SecondGlyph == segundo:
                        return getattr(par.Value1, "XAdvance", 0) if par.Value1 else 0
            elif sub.Format == 2:
                classe1 = sub.ClassDef1.classDefs.get(primeiro, 0)
                classe2 = sub.ClassDef2.classDefs.get(segundo, 0)
                registro = sub.Class1Record[classe1].Class2Record[classe2]
                return getattr(registro.Value1, "XAdvance", 0) if registro.Value1 else 0
        return 0


def compor_texto(
    texto: str,
    fonte: Fonte,
    capitular: float,
    x: float,
    linha_base: float,
) -> tuple[list, tuple[float, float, float, float]]:
    """Compõe o texto numa linha, com a altura de capitular pedida.

    Devolve a gravação dos contornos (y para baixo) e os limites da tinta
    (xMin, yMin, xMax, yMax), nas unidades da composição. O tamanho é dado
    pela capitular, e não pelo corpo, porque o que precisa casar com o
    símbolo é a altura das maiúsculas.
    """
    gravacao = RecordingPen()
    escala = capitular / fonte.capitular
    milesimo = fonte.upem / 1000
    avanco = 0.0
    anterior: tuple[str, str] | None = None
    for caractere in texto:
        glifo = fonte.cmap[ord(caractere)]
        if anterior is not None:
            ajuste = AJUSTES_OPTICOS.get((anterior[1], caractere), 0) * milesimo
            avanco += (fonte.kern(anterior[0], glifo) + ajuste) * escala
        pena = TransformPen(gravacao, (escala, 0, 0, -escala, x + avanco, linha_base))
        replayRecording(fonte.contornos(glifo), pena)
        avanco += fonte.metricas[glifo][0] * escala
        anterior = (glifo, caractere)
    limites = BoundsPen(None)
    replayRecording(gravacao.value, limites)
    return gravacao.value, limites.bounds


def deslocar(contornos: list, dx: float, dy: float) -> list:
    gravacao = RecordingPen()
    replayRecording(contornos, TransformPen(gravacao, (1, 0, 0, 1, dx, dy)))
    return gravacao.value


def transformar(formas: list, escala: float, dx: float, dy: float) -> list:
    """Escala e desloca formas, para compor uma marca dentro de outra imagem."""
    resultado = []
    for forma in formas:
        if isinstance(forma, Retangulo):
            resultado.append(
                Retangulo(
                    forma.x * escala + dx,
                    forma.y * escala + dy,
                    forma.largura * escala,
                    forma.altura * escala,
                    forma.raio * escala,
                    forma.cor,
                )
            )
        else:
            gravacao = RecordingPen()
            replayRecording(
                forma.contornos, TransformPen(gravacao, (escala, 0, 0, escala, dx, dy))
            )
            resultado.append(Caminho(gravacao.value, forma.cor))
    return resultado


# ---------------------------------------------------------------------------
# As três composições
# ---------------------------------------------------------------------------


def composicao_simbolo(variante: Variante) -> Composicao:
    """Só o símbolo, sangrado: é ícone, e ícone ocupa o quadrado inteiro."""
    return Composicao(LADO, LADO, formas_simbolo(variante))


def composicao_horizontal(
    variante: Variante, parametros: Parametros = PADRAO
) -> Composicao:
    """Símbolo à esquerda e nome à direita, capitulares centradas no símbolo."""
    respiro = parametros.respiro
    capitular = parametros.capitular_horizontal
    linha_base = respiro + LADO / 2 + capitular / 2
    contornos, (x_min, _, x_max, _) = compor_texto(
        "SLAP Mobile", Fonte.abrir(parametros.fonte), capitular, 0.0, linha_base
    )
    # O espaço é medido até a tinta, não até a caixa do glifo.
    deslocamento = respiro + LADO + parametros.espaco_horizontal - x_min
    formas = formas_simbolo(variante, respiro, respiro)
    formas.append(Caminho(deslocar(contornos, deslocamento, 0.0), variante.tinta))
    return Composicao(
        x_max + deslocamento + respiro, LADO + 2 * respiro, formas, variante.fundo
    )


def composicao_vertical(
    variante: Variante, parametros: Parametros = PADRAO
) -> Composicao:
    """Símbolo em cima e nome centrado abaixo."""
    respiro = parametros.respiro
    capitular = parametros.capitular_vertical
    linha_base = respiro + LADO + parametros.espaco_vertical + capitular
    contornos, (x_min, _, x_max, y_max) = compor_texto(
        "SLAP Mobile", Fonte.abrir(parametros.fonte), capitular, 0.0, linha_base
    )
    largura_texto = x_max - x_min
    largura = max(LADO, largura_texto) + 2 * respiro
    formas = formas_simbolo(variante, (largura - LADO) / 2, respiro)
    formas.append(
        Caminho(
            deslocar(contornos, (largura - largura_texto) / 2 - x_min, 0.0),
            variante.tinta,
        )
    )
    return Composicao(largura, y_max + respiro, formas, variante.fundo)


# ---------------------------------------------------------------------------
# SVG
# ---------------------------------------------------------------------------


def _n(valor: float) -> str:
    texto = f"{valor:.3f}".rstrip("0").rstrip(".")
    return "0" if texto == "-0" else texto


def _hex(cor: Cor) -> str:
    return "#%02X%02X%02X" % cor


def caminho_retangulo(r: Retangulo, horario: bool = True) -> str:
    """Retângulo de cantos redondos como caminho SVG, no sentido pedido.

    O sentido importa: o vazado das barras na versão monocromática é um
    subcaminho no sentido contrário ao do quadrado, e assim fica furado tanto
    por `nonzero` quanto por `evenodd`.
    """
    x, y, largura, altura, raio = r.x, r.y, r.largura, r.altura, r.raio
    varredura = 1 if horario else 0

    def arco(px: float, py: float) -> str:
        return f"A{_n(raio)} {_n(raio)} 0 0 {varredura} {_n(px)} {_n(py)}"

    def reta(comando: str, valor: float, atual: float) -> str:
        if math.isclose(valor, atual, abs_tol=1e-6):
            return ""
        return f"{comando}{_n(valor)}"

    if horario:
        partes = [
            f"M{_n(x + raio)} {_n(y)}",
            reta("H", x + largura - raio, x + raio),
            arco(x + largura, y + raio),
            reta("V", y + altura - raio, y + raio),
            arco(x + largura - raio, y + altura),
            reta("H", x + raio, x + largura - raio),
            arco(x, y + altura - raio),
            reta("V", y + raio, y + altura - raio),
            arco(x + raio, y),
            "Z",
        ]
    else:
        partes = [
            f"M{_n(x + raio)} {_n(y)}",
            arco(x, y + raio),
            reta("V", y + altura - raio, y + raio),
            arco(x + raio, y + altura),
            reta("H", x + largura - raio, x + raio),
            arco(x + largura, y + altura - raio),
            reta("V", y + raio, y + altura - raio),
            arco(x + largura - raio, y),
            "Z",
        ]
    return "".join(parte for parte in partes if parte)


def caminho_contornos(contornos: list) -> str:
    pena = SVGPathPen(None, ntos=_n)
    replayRecording(contornos, pena)
    return pena.getCommands()


def svg(composicao: Composicao, titulo: str) -> str:
    """Serializa a composição.

    Formas sem cor são vazados: entram como subcaminho, no sentido contrário,
    do último caminho desenhado.
    """
    elementos: list[str] = []
    dados: list[str] = []  # o `d` de cada elemento, para receber vazados
    if composicao.fundo is not None:
        elementos.append(
            f'<rect width="{_n(composicao.largura)}" '
            f'height="{_n(composicao.altura)}" fill="{_hex(composicao.fundo)}"/>'
        )
        dados.append("")
    for forma in composicao.formas:
        if isinstance(forma, Retangulo) and forma.cor is None:
            dados[-1] += caminho_retangulo(forma, horario=False)
            elementos[-1] = f'<path fill="{_cor_do(elementos[-1])}" d="{dados[-1]}"/>'
            continue
        if isinstance(forma, Retangulo):
            dados.append(caminho_retangulo(forma))
        else:
            dados.append(caminho_contornos(forma.contornos))
        elementos.append(f'<path fill="{_hex(forma.cor)}" d="{dados[-1]}"/>')
    corpo = "\n  ".join(elementos)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {_n(composicao.largura)} {_n(composicao.altura)}">\n'
        "  <!-- Gerado por tool/gerar_marca.py; não editar à mão. -->\n"
        f"  <title>{titulo}</title>\n"
        f"  {corpo}\n"
        "</svg>\n"
    )


def _cor_do(elemento: str) -> str:
    inicio = elemento.index('fill="') + len('fill="')
    return elemento[inicio : elemento.index('"', inicio)]


# ---------------------------------------------------------------------------
# PNG
# ---------------------------------------------------------------------------


class PenaAchatadora(BasePen):
    """Reduz curvas a polígonos, para o Pillow preencher."""

    def __init__(self, escala: float):
        super().__init__(None)
        self.escala = escala
        self.contornos: list[list[tuple[float, float]]] = []
        self._atual: list[tuple[float, float]] = []

    def _ponto(self, p: tuple[float, float]) -> tuple[float, float]:
        return (p[0] * self.escala, p[1] * self.escala)

    def _moveTo(self, p):
        self._atual = [self._ponto(p)]
        self.contornos.append(self._atual)

    def _lineTo(self, p):
        self._atual.append(self._ponto(p))

    def _amostrar(self, pontos: list[tuple[float, float]]) -> None:
        # Número de segmentos proporcional ao comprimento em pixels.
        comprimento = sum(math.dist(a, b) for a, b in zip(pontos, pontos[1:]))
        n = max(4, min(64, math.ceil(comprimento / 4)))
        grau = len(pontos) - 1
        for i in range(1, n + 1):
            t = i / n
            camada = list(pontos)  # De Casteljau
            for _ in range(grau):
                camada = [
                    ((1 - t) * a[0] + t * b[0], (1 - t) * a[1] + t * b[1])
                    for a, b in zip(camada, camada[1:])
                ]
            self._atual.append(camada[0])

    def _curveToOne(self, p1, p2, p3):
        inicio = self._ponto(self._getCurrentPoint())
        self._amostrar([inicio, self._ponto(p1), self._ponto(p2), self._ponto(p3)])

    def _qCurveToOne(self, p1, p2):
        inicio = self._ponto(self._getCurrentPoint())
        self._amostrar([inicio, self._ponto(p1), self._ponto(p2)])

    def _closePath(self):
        pass

    def _endPath(self):
        pass


def _area_com_sinal(poligono: list[tuple[float, float]]) -> float:
    soma = 0.0
    for (x0, y0), (x1, y1) in zip(poligono, poligono[1:] + poligono[:1]):
        soma += x0 * y1 - x1 * y0
    return soma / 2


def mascara_contornos(tamanho: tuple[int, int], contornos: list) -> Image.Image:
    """Preenche contornos de fonte: os externos somam, os internos (sentido
    contrário) vazam. Basta para fontes sem contornos sobrepostos, caso das
    que o projeto embarca."""
    mascara = Image.new("L", tamanho, 0)
    pincel = ImageDraw.Draw(mascara)
    areas = [_area_com_sinal(c) for c in contornos]
    sentido_externo = math.copysign(1, max(areas, key=abs))
    for contorno, area in zip(contornos, areas):
        if math.copysign(1, area) == sentido_externo:
            pincel.polygon(contorno, fill=255)
    for contorno, area in zip(contornos, areas):
        if area != 0 and math.copysign(1, area) != sentido_externo:
            pincel.polygon(contorno, fill=0)
    return mascara


def rasterizar(composicao: Composicao, largura: int) -> Image.Image:
    """Desenha a composição com `largura` pixels; a altura sai da proporção.

    Cor e recorte andam em imagens separadas — a tinta num RGB e a silhueta
    numa máscara —, e só no fim viram um RGBA. Reduzir um RGBA direto mistura
    a cor dos pixels transparentes na borda e deixa auréola; assim, não.

    Desenho em resolução maior e redução no fim, como em gerar_icones.py.
    """
    escala = largura / composicao.largura
    altura = max(1, round(composicao.altura * escala))
    superamostragem = max(2, min(16, math.ceil(4096 / largura)))
    grande = (largura * superamostragem, altura * superamostragem)
    k = escala * superamostragem

    opaca = composicao.fundo is not None
    # Sem fundo, a base fica na cor da tinta: a borda externa então mistura
    # tinta com tinta, e não tinta com o vazio.
    base = composicao.fundo or _tinta_principal(composicao)
    cor = Image.new("RGB", grande, base)
    silhueta = Image.new("L", grande, 255 if opaca else 0)
    pincel_cor = ImageDraw.Draw(cor)
    pincel_silhueta = ImageDraw.Draw(silhueta)

    for forma in composicao.formas:
        vazado = forma.cor is None
        if isinstance(forma, Retangulo):
            caixa = (
                forma.x * k,
                forma.y * k,
                (forma.x + forma.largura) * k,
                (forma.y + forma.altura) * k,
            )
            if vazado and opaca:
                pincel_cor.rounded_rectangle(caixa, radius=forma.raio * k, fill=base)
            elif vazado:
                pincel_silhueta.rounded_rectangle(caixa, radius=forma.raio * k, fill=0)
            else:
                raio = forma.raio * k
                pincel_cor.rounded_rectangle(caixa, radius=raio, fill=forma.cor)
                pincel_silhueta.rounded_rectangle(caixa, radius=raio, fill=255)
        else:
            pena = PenaAchatadora(k)
            replayRecording(forma.contornos, pena)
            mascara = mascara_contornos(grande, pena.contornos)
            cor.paste(forma.cor, None, mascara)
            silhueta.paste(255, None, mascara)

    imagem = cor.resize((largura, altura), Image.LANCZOS)
    if opaca:
        return imagem
    imagem = imagem.convert("RGBA")
    imagem.putalpha(silhueta.resize((largura, altura), Image.LANCZOS))
    return imagem


def _tinta_principal(composicao: Composicao) -> Cor:
    for forma in composicao.formas:
        if forma.cor is not None:
            return forma.cor
    return BRANCO


# ---------------------------------------------------------------------------
# Saída
# ---------------------------------------------------------------------------

TAMANHOS_SIMBOLO = (24, 48, 192, 512, 1024)
LARGURAS_COMPOSICAO = (400, 800, 1600)
LARGURA_CANONICA = 800  # docs/marca/horizontal-claro.png


def _gravar(destino: Path, conteudo: str | Image.Image) -> None:
    destino.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(conteudo, str):
        destino.write_text(conteudo, encoding="utf-8")
    else:
        conteudo.save(destino, optimize=True)
    print(destino.relative_to(RAIZ))


def marca() -> None:
    for variante in VARIANTES:
        composicoes = {
            "simbolo": (composicao_simbolo(variante), TAMANHOS_SIMBOLO),
            "horizontal": (composicao_horizontal(variante), LARGURAS_COMPOSICAO),
            "vertical": (composicao_vertical(variante), LARGURAS_COMPOSICAO),
        }
        for nome, (composicao, tamanhos) in composicoes.items():
            titulo = "SLAP Mobile" + (" — símbolo" if nome == "simbolo" else "")
            _gravar(MARCA / f"{nome}-{variante.nome}.svg", svg(composicao, titulo))
            for tamanho in tamanhos:
                _gravar(
                    MARCA / "png" / f"{nome}-{variante.nome}-{tamanho}.png",
                    rasterizar(composicao, tamanho),
                )
    # A cópia de nome fixo, sem o tamanho: é a que o README e o site apontam,
    # e o nome não pode mudar quando o tamanho de exportação mudar.
    _gravar(
        MARCA / "horizontal-claro.png",
        rasterizar(composicao_horizontal(VARIANTES[0]), LARGURA_CANONICA),
    )


def destaque() -> None:
    """Imagem de destaque da Play Store: 1024 × 500, sem transparência.

    A logomarca horizontal na versão clara, com a frase da listagem embaixo,
    o bloco inteiro centrado. Fundo claro para o quadrado teal aparecer como
    o usuário vai ver o ícone na própria loja.

    Tudo fica a mais de 90 px das bordas, que a loja pode cortar. O centro não
    é reservado: a listagem não tem vídeo, então não há botão sobreposto.
    """
    largura, altura = 1024, 500
    horizontal = composicao_horizontal(VARIANTES[0])
    largura_marca = 700.0
    escala = largura_marca / horizontal.largura
    altura_marca = horizontal.altura * escala

    fonte = Fonte.abrir("PublicSans-Regular.ttf")
    frase = ["Inventário patrimonial offline,", "sincronizado direto entre celulares."]
    capitular, entrelinha = 26.0, 46.0
    altura_frase = capitular + entrelinha
    # O respiro da própria marca já separa as duas partes; a folga é o resto.
    folga = 14.0
    topo = (altura - (altura_marca + folga + altura_frase)) / 2

    formas = transformar(
        horizontal.formas, escala, (largura - largura_marca) / 2, topo
    )
    base_frase = topo + altura_marca + folga + capitular
    for n, linha in enumerate(frase):
        contornos, (x_min, _, x_max, _) = compor_texto(
            linha, fonte, capitular, 0.0, base_frase + n * entrelinha
        )
        contornos = deslocar(contornos, (largura - (x_max - x_min)) / 2 - x_min, 0.0)
        formas.append(Caminho(contornos, TINTA_SECUNDARIA))

    imagem = rasterizar(Composicao(largura, altura, formas, FUNDO_CLARO), largura)
    _gravar(RAIZ / "docs/loja/destaque.png", imagem)


if __name__ == "__main__":
    marca()
    destaque()
