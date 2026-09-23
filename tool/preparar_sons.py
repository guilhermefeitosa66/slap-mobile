#!/usr/bin/env python3
"""Prepara os sons de retorno a partir dos originais do SLAP.

Os três sons vêm do sistema web atual (`slap/public/`). Preservá-los importa:
a comissão de inventário já associa cada bipe a um resultado, e trocá-los
obrigaria a reaprender o que já é automático.

O timbre não é alterado. Duas correções são aplicadas, ambas por defeito real
medido nos arquivos originais:

1. **Silêncio no fim é removido.** O som de sucesso tem 1300 ms, dos quais
   361 ms são silêncio. Como ele toca a cada patrimônio lido, esse silêncio
   vira atraso percebido entre uma leitura e a seguinte.

2. **Volumes são igualados.** O som de "já verificado" tem pico 8700 contra
   ~27000 dos outros — quase três vezes mais baixo. É justamente o aviso que
   não pode passar despercebido em corredor ou sala de aula cheia.

Uso:
    python3 tool/preparar_sons.py [caminho/para/slap/public]
"""

import struct
import sys
import wave
from pathlib import Path

# Nome no SLAP -> nome semântico no aplicativo.
SONS = {
    "success-2.wav": "sucesso.wav",
    "alert.wav": "ja_verificado.wav",
    "error.wav": "nao_localizado.wav",
}

# Fração do pico abaixo da qual a amostra conta como silêncio.
LIMIAR_SILENCIO = 0.02

# Pico alvo, em fração do máximo de 16 bits. Deixa margem para não estourar
# em alto-falante de celular, que distorce bem antes do limite teórico.
PICO_ALVO = 0.89


def ler(caminho: Path):
    with wave.open(str(caminho), "rb") as f:
        if f.getsampwidth() != 2 or f.getnchannels() != 1:
            raise SystemExit(f"{caminho.name}: esperado WAV mono de 16 bits.")
        quadros = f.getnframes()
        amostras = struct.unpack(f"<{quadros}h", f.readframes(quadros))
        return list(amostras), f.getframerate()


def aparar(amostras: list[int]) -> list[int]:
    """Remove silêncio do começo e do fim, sem tocar no meio."""
    pico = max((abs(a) for a in amostras), default=0)
    if pico == 0:
        return amostras

    limite = pico * LIMIAR_SILENCIO
    inicio = next((i for i, a in enumerate(amostras) if abs(a) > limite), 0)
    fim = next(
        (i for i in range(len(amostras) - 1, -1, -1) if abs(amostras[i]) > limite),
        len(amostras) - 1,
    )
    return amostras[inicio : fim + 1]


def normalizar(amostras: list[int]) -> list[int]:
    pico = max((abs(a) for a in amostras), default=0)
    if pico == 0:
        return amostras

    ganho = (PICO_ALVO * 32767) / pico
    return [max(-32768, min(32767, int(a * ganho))) for a in amostras]


def suavizar_bordas(amostras: list[int], taxa: int) -> list[int]:
    """Rampa de 3 ms nas pontas, para o corte não estalar no alto-falante."""
    rampa = max(1, int(taxa * 0.003))
    total = len(amostras)
    if total < rampa * 2:
        return amostras

    saida = list(amostras)
    for i in range(rampa):
        fator = i / rampa
        saida[i] = int(saida[i] * fator)
        saida[total - 1 - i] = int(saida[total - 1 - i] * fator)
    return saida


def main() -> None:
    origem = Path(
        sys.argv[1] if len(sys.argv) > 1 else Path.home() / "projetos/ifpi/slap/public"
    )
    destino = Path(__file__).resolve().parent.parent / "assets" / "sons"
    destino.mkdir(parents=True, exist_ok=True)

    for nome_slap, nome_app in SONS.items():
        entrada = origem / nome_slap
        if not entrada.exists():
            raise SystemExit(f"Não encontrei {entrada}. Informe o caminho do SLAP.")

        amostras, taxa = ler(entrada)
        antes = len(amostras) / taxa * 1000

        amostras = suavizar_bordas(normalizar(aparar(amostras)), taxa)
        depois = len(amostras) / taxa * 1000

        saida = destino / nome_app
        with wave.open(str(saida), "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(taxa)
            f.writeframes(b"".join(struct.pack("<h", a) for a in amostras))

        print(f"{nome_slap} -> {nome_app}  {antes:.0f}ms -> {depois:.0f}ms")


if __name__ == "__main__":
    main()
