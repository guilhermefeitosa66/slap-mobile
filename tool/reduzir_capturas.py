#!/usr/bin/env python3
"""Reduz capturas de tela do emulador para o README e o site.

O emulador entrega PNGs de 1344 × 2992 (o Pixel de referência), pesados demais
para uma página que mostra doze deles. Este script os reduz para 720 px de
largura, mantendo a proporção, e grava em docs/imagens/ com os nomes de
CAPTURAS, abaixo, que são os que o README, o manual e o site usam.

    python3 tool/reduzir_capturas.py <pasta com as capturas> [largura]

Os arquivos de entrada se chamam <nome>.png, com <nome> em CAPTURAS
(identidade, painel, levantamento…). O que não tiver esse nome
é ignorado com aviso. O procedimento inteiro está em docs/imagens/README.md.

Requer Pillow.
"""

import sys
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "docs" / "imagens"
LARGURA_PADRAO = 720

# As capturas de docs/imagens/. A mesma lista, com o texto alternativo de cada
# uma, está no gerador do site (repositório site-slap-libre-apps-org); um nome
# novo aqui precisa entrar lá também.
CAPTURAS = (
    "identidade",
    "inventarios",
    "importacao",
    "painel",
    "compartilhar",
    "configuracao",
    "levantamento",
    "camera",
    "sincronizacao",
    "itens",
    "filtros",
    "detalhe",
    "relatorios",
)


def nomes_esperados() -> set[str]:
    return set(CAPTURAS)


def reduzir(origem: Path, largura: int) -> None:
    esperados = nomes_esperados()
    DESTINO.mkdir(parents=True, exist_ok=True)

    for arquivo in sorted(origem.glob("*.png")):
        if arquivo.stem not in esperados:
            print(f"ignorado (nome fora de CAPTURAS): {arquivo.name}", file=sys.stderr)
            continue
        with Image.open(arquivo) as imagem:
            proporcao = largura / imagem.width
            altura = round(imagem.height * proporcao)
            reduzida = imagem.convert("RGB").resize((largura, altura), Image.LANCZOS)
            # Interface chapada usa poucas cores: a paleta de 256 corta o
            # arquivo a um terço sem diferença visível. Só a tela da câmera,
            # que é foto, perde um pouco — e é a que menos depende de detalhe.
            paleta = reduzida.quantize(colors=256, method=Image.MEDIANCUT)
            saida = DESTINO / arquivo.name
            paleta.save(saida, optimize=True)
            tamanho = saida.stat().st_size // 1024
            print(f"{saida.relative_to(RAIZ)}: {largura} × {altura}, {tamanho} kB")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    reduzir(Path(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else LARGURA_PADRAO)
