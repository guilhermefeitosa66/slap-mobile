#!/usr/bin/env python3
"""Gera os três sons de feedback do levantamento.

Os sons precisam ser distinguíveis sem olhar para a tela: o usuário faz o
levantamento apontando o leitor para os patrimônios, não olhando o celular.
São desenhados para contrastar em três dimensões ao mesmo tempo — altura,
número de pulsos e direção — para que continuem distinguíveis em ambiente
ruidoso e com o celular no bolso ou na mão:

    sucesso        um pulso, agudo, subindo     (C6→E6)
    ja_verificado  dois pulsos, médio, constante (G5 G5)
    nao_localizado um pulso longo, grave, descendo (A3→A2)

Gerados em código, e não baixados de um banco de sons, para que a licença do
repositório se aplique a eles sem ressalva.

Uso: python3 tool/gerar_sons.py
"""

import math
import struct
import wave
from pathlib import Path

TAXA = 44100
AMPLITUDE = 0.55


def envelope(i: int, total: int) -> float:
    """Ataque e decaimento suaves, para não estalar no alto-falante."""
    ataque = int(TAXA * 0.005)
    decaimento = int(total * 0.35)
    if i < ataque:
        return i / ataque
    if i > total - decaimento:
        return max(0.0, (total - i) / decaimento)
    return 1.0


def tom(freq_inicial: float, freq_final: float, ms: int, harmonico: float = 0.0):
    """Senoide com varredura linear de frequência.

    `harmonico` mistura a segunda harmônica: 0 dá um tom puro e limpo, valores
    maiores dão aspereza, usada para o som de erro.
    """
    total = int(TAXA * ms / 1000)
    fase = 0.0
    for i in range(total):
        freq = freq_inicial + (freq_final - freq_inicial) * (i / total)
        fase += 2 * math.pi * freq / TAXA
        amostra = math.sin(fase) + harmonico * math.sin(2 * fase)
        yield amostra / (1 + harmonico) * envelope(i, total) * AMPLITUDE


def silencio(ms: int):
    for _ in range(int(TAXA * ms / 1000)):
        yield 0.0


def escrever(caminho: Path, amostras) -> None:
    quadros = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, a)) * 32767)) for a in amostras
    )
    with wave.open(str(caminho), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(TAXA)
        f.writeframes(quadros)
    print(f"{caminho}  {len(quadros) / 2 / TAXA * 1000:.0f} ms")


def main() -> None:
    destino = Path(__file__).resolve().parent.parent / "assets" / "sons"
    destino.mkdir(parents=True, exist_ok=True)

    # Sucesso: curto e agudo, subindo. Não pode cansar — toca milhares de vezes.
    escrever(destino / "sucesso.wav", tom(1046.5, 1318.5, 90))

    # Já verificado: dois pulsos. O padrão rítmico é o que distingue, mais
    # confiável que a altura quando há ruído de fundo.
    escrever(
        destino / "ja_verificado.wav",
        list(tom(784.0, 784.0, 70)) + list(silencio(60)) + list(tom(784.0, 784.0, 70)),
    )

    # Não localizado: longo, grave, descendo e áspero. Exige atenção porque
    # significa que algo precisa ser conferido à mão.
    escrever(destino / "nao_localizado.wav", tom(220.0, 110.0, 300, harmonico=0.4))


if __name__ == "__main__":
    main()
