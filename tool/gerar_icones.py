#!/usr/bin/env python3
"""Gera o ícone do aplicativo em todas as densidades, a partir da geometria.

O ícone é o motivo do código de barras do design: cinco barras brancas de
ponta arredondada, a quarta mais curta, sobre o teal institucional. A mesma
geometria está em `IconeCodigoBarras` (lib/app/componentes.dart) e nos
vetores do Android (res/drawable/ic_launcher_foreground.xml), numa grade de
24 unidades:

    barras em x = 3, 7, 11, 15, 19
    de y = 5 até y = 19 (a quarta até y = 15)
    traço de 2 unidades, ponta redonda

Gerar em vez de desenhar à mão mantém os três lugares idênticos, e refazer
tudo depois de um ajuste é rodar este script de novo.

O que sai:

- Android, antes do ícone adaptativo (API < 26): mipmap-*/ic_launcher.png,
  quadrado de cantos arredondados com transparência fora dele.
- iOS: AppIcon.appiconset, sangrado e opaco (o sistema recorta os cantos, e
  a App Store recusa ícone com transparência).
- docs/loja/icone-512.png: o ícone de alta resolução da Play Store.
- docs/loja/destaque.png: a imagem de destaque da Play Store (1024 × 500),
  com o mesmo motivo e as fontes do aplicativo.

O ícone adaptativo do Android (API 26+) e o monocromático dos ícones com tema
(Android 13+) são vetores e não passam por aqui.

Uso:
    python3 tool/gerar_icones.py

Requer Pillow.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent

TEAL = (0x0F, 0x5C, 0x52)
TEAL_CLARO = (0xDC, 0xE9, 0xE6)
BRANCO = (0xFF, 0xFF, 0xFF)

BARRAS = [(3, 19), (7, 19), (11, 19), (15, 15), (19, 19)]
TOPO = 5

# Fração do lado do ícone ocupada pela grade de 24 unidades. No ícone
# adaptativo cada unidade mede 2,2 dp, e o motivo ocupa cerca de 55% dos
# 72 dp visíveis; aqui a proporção é a mesma, para o ícone não mudar de
# tamanho entre versões do Android.
UNIDADE_DP = 2.2
ESCALA_DA_GRADE = UNIDADE_DP * 24 / 72

# Desenho em resolução maior e redução no fim: é o que suaviza as bordas.
SUPERAMOSTRAGEM = 8


def desenhar(lado: int, *, cantos: float, transparente_fora: bool) -> Image.Image:
    """Desenha o ícone num quadrado de `lado` pixels.

    `cantos` é o raio dos cantos em fração do lado (0 para quadrado).
    """
    grande = lado * SUPERAMOSTRAGEM
    fundo = (0, 0, 0, 0) if transparente_fora else TEAL + (255,)
    imagem = Image.new("RGBA", (grande, grande), fundo)
    pincel = ImageDraw.Draw(imagem)

    if transparente_fora:
        pincel.rounded_rectangle(
            (0, 0, grande - 1, grande - 1),
            radius=int(grande * cantos),
            fill=TEAL + (255,),
        )

    unidade = grande * ESCALA_DA_GRADE / 24
    centro = grande / 2
    # Centro da grade: meio das barras em x (11) e em y (12).
    def ponto(x: float, y: float) -> tuple[float, float]:
        return (centro + (x - 11) * unidade, centro + (y - 12) * unidade)

    raio = unidade  # traço de 2 unidades
    for x, fim in BARRAS:
        (x0, y0), (_, y1) = ponto(x, TOPO), ponto(x, fim)
        pincel.rounded_rectangle(
            (x0 - raio, y0 - raio, x0 + raio, y1 + raio),
            radius=raio,
            fill=BRANCO + (255,),
        )

    return imagem.resize((lado, lado), Image.LANCZOS)


def android() -> None:
    densidades = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for nome, lado in densidades.items():
        destino = RAIZ / f"android/app/src/main/res/mipmap-{nome}/ic_launcher.png"
        desenhar(lado, cantos=0.22, transparente_fora=True).save(destino, optimize=True)
        print(destino.relative_to(RAIZ))


def ios() -> None:
    pasta = RAIZ / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    indice = json.loads((pasta / "Contents.json").read_text())
    for entrada in indice["images"]:
        lado_pt = float(entrada["size"].split("x")[0])
        escala = int(entrada["scale"].rstrip("x"))
        lado = round(lado_pt * escala)
        destino = pasta / entrada["filename"]
        # Opaco: a App Store recusa ícone com canal alfa.
        desenhar(lado, cantos=0, transparente_fora=False).convert("RGB").save(
            destino, optimize=True
        )
        print(destino.relative_to(RAIZ))


def loja() -> None:
    destino = RAIZ / "docs/loja/icone-512.png"
    destino.parent.mkdir(parents=True, exist_ok=True)
    # A Play Store aplica a própria máscara; o arquivo vai sangrado e opaco.
    desenhar(512, cantos=0, transparente_fora=False).convert("RGB").save(
        destino, optimize=True
    )
    print(destino.relative_to(RAIZ))



def destaque() -> None:
    """Imagem de destaque da Play Store: 1024 × 500, sem transparência.

    A loja pode cortar as bordas e sobrepor o botão de vídeo no centro; o
    motivo e o texto ficam longe das bordas e não dependem do meio.
    """
    largura, altura = 1024, 500
    s = SUPERAMOSTRAGEM // 2
    imagem = Image.new("RGB", (largura * s, altura * s), TEAL)
    pincel = ImageDraw.Draw(imagem)

    # O motivo, grande, à esquerda: a mesma grade de 24 unidades.
    unidade = 11 * s
    centro_x, centro_y = 190 * s, altura * s / 2
    raio = unidade
    for x, fim in BARRAS:
        x0 = centro_x + (x - 11) * unidade
        y0 = centro_y + (TOPO - 12) * unidade
        y1 = centro_y + (fim - 12) * unidade
        pincel.rounded_rectangle(
            (x0 - raio, y0 - raio, x0 + raio, y1 + raio), radius=raio, fill=BRANCO
        )

    fontes = RAIZ / "assets/fontes"
    titulo = ImageFont.truetype(str(fontes / "Archivo-SemiBold.ttf"), 84 * s)
    texto = ImageFont.truetype(str(fontes / "PublicSans-Regular.ttf"), 32 * s)
    esquerda = 380 * s
    pincel.text((esquerda, 150 * s), "SLAP Mobile", font=titulo, fill=BRANCO)
    linhas = ["Inventário patrimonial offline,", "sincronizado direto entre celulares."]
    for n, linha in enumerate(linhas):
        pincel.text((esquerda, (272 + n * 46) * s), linha, font=texto, fill=TEAL_CLARO)

    destino = RAIZ / "docs/loja/destaque.png"
    imagem.resize((largura, altura), Image.LANCZOS).save(destino, optimize=True)
    print(destino.relative_to(RAIZ))


if __name__ == "__main__":
    android()
    ios()
    loja()
    destaque()
