#!/usr/bin/env python3
"""Gera o site estático publicado no GitHub Pages.

O site apresenta o aplicativo — o que é, como se parece, como se usa e como
instalar — e publica a política de privacidade numa URL estável, que as lojas
exigem. A fonte da verdade dos textos longos continua no repositório: a
política vem de docs/privacidade.md, o manual de docs/manual.md, as capturas
de docs/imagens/ e a logomarca de docs/marca/. Este script só monta as páginas, com a paleta e as
fontes do aplicativo, para o site nunca divergir do que está versionado.

    python3 tool/gerar_site.py [pasta de saída, padrão _site]

Saída:
    index.html                   apresentação, como usar, capturas, instalação
    manual/index.html            o manual completo, de docs/manual.md
    privacidade/index.html       a política
    entrar/index.html            reserva do link de entrada num inventário
    .well-known/assetlinks.json  verificação do App Link (ver abaixo)
    fontes/, imagens/, marca/    o que as páginas usam
    icone.png

O convite de entrada num inventário é um App Link para /slap-mobile/entrar.
Para o Android abrir o aplicativo direto, em vez de oferecer o seletor, o site
precisa servir o assetlinks.json com a impressão digital SHA-256 da chave de
release. Ela não está no repositório: grave-a em docs/loja/impressao-digital.txt
(só os 32 pares hexadecimais separados por dois-pontos) na máquina que guarda a
chave, ou passe SLAP_IMPRESSAO_DIGITAL no ambiente do workflow. Sem ela o site
sai sem o arquivo, e o link continua funcionando pelo seletor de aplicativos.

Depende do pacote `markdown` (pip install markdown).
"""

import html
import json
import os
import re
import shutil
import sys
from pathlib import Path

import markdown
from markdown.extensions.toc import slugify_unicode

RAIZ = Path(__file__).resolve().parent.parent
REPOSITORIO = "https://github.com/guilhermefeitosa66/slap-mobile"
RELEASE = f"{REPOSITORIO}/releases/latest"
SITE = "https://guilhermefeitosa66.github.io/slap-mobile/"
PACOTE_ANDROID = "io.github.guilhermefeitosa66.slap_mobile"

# docs/privacidade.md e o que ele cita por caminho relativo.
FONTE_POLITICA = RAIZ / "docs" / "privacidade.md"
# O manual completo, também escrito em Markdown no repositório: assim ele é
# lido e revisado ao lado do código, em vez de virar string dentro deste
# gerador.
FONTE_MANUAL = RAIZ / "docs" / "manual.md"
PASTA_IMAGENS = RAIZ / "docs" / "imagens"
PASTA_MARCA = RAIZ / "docs" / "marca"

# Impressão digital SHA-256 da chave de release, para o assetlinks.json.
FONTE_IMPRESSAO = RAIZ / "docs" / "loja" / "impressao-digital.txt"
IMPRESSAO_DIGITAL = re.compile(r"^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$")

FONTES = {
    "Archivo-SemiBold.ttf": ("Archivo", 600),
    "PublicSans-Regular.ttf": ("Public Sans", 400),
    "PublicSans-SemiBold.ttf": ("Public Sans", 600),
}

# Capturas de tela usadas nas páginas: arquivo em docs/imagens/ e o texto
# alternativo. Quem gera as capturas é docs/imagens/README.md.
CAPTURAS = {
    "identidade": "Tela de identificação: nome e matrícula, sem senha",
    "inventarios": "Lista de inventários do aparelho",
    "importacao": "Conferência das colunas da planilha do SUAP antes de importar",
    "painel": "Painel do inventário: progresso e os três grupos de patrimônios",
    "compartilhar": "Compartilhar o inventário por QR code ou link",
    "configuracao": "Configuração das leituras: sala, responsável, estado e situação",
    "levantamento": "Levantamento: leitura registrada, com a lista das últimas leituras",
    "camera": "Leitura do código de barras pela câmera",
    "sincronizacao": "Sincronização com os outros aparelhos da rede local",
    "itens": "Todos os itens, com busca e filtros por sala, responsável e situação",
    "filtros": "Filtro por sala, responsável, estado, situação e quem verificou",
    "detalhe": "Detalhe de um patrimônio: dados da planilha e do levantamento",
    "relatorios": "Relatórios em XLSX ou CSV, um por grupo",
}

# Logomarca horizontal em fundo claro, para o cabeçalho e a abertura.
LOGO = "horizontal-claro.png"

# Mesmos tokens de lib/app/tema.dart (PaletaClara e CoresResultado.claro).
# O site é só em tema claro: é a cara do aplicativo na loja e no README.
ESTILO = """
:root {
  color-scheme: light;
  --fundo: #F7F6F3; --superficie: #FFFFFF; --tinta: #14201E;
  --tinta-secundaria: #55625F; --teal: #0F5C52; --teal-claro: #DCE9E6;
  --sobre-teal-claro: #0B3B34; --borda: #E2E0DA; --trilho: #EDEBE4;
  --verde-fundo: #DFF0E4; --verde-texto: #0F5C2E;
  --laranja-fundo: #FBE8D6; --laranja-texto: #8A4408;
  --vermelho-fundo: #FAE0DE; --vermelho-texto: #7E1214;
  --raio: 16px; --largura: 1080px;
  /* Contorno das capturas: mais presente que --borda, porque o fundo da
     página e o do aplicativo em tema claro são quase a mesma cor. */
  --borda-captura: #D3D0C7;
}
FONTES
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0; background: var(--fundo); color: var(--tinta);
  font: 400 17px/1.6 "Public Sans", system-ui, sans-serif;
  -webkit-text-size-adjust: 100%;
}
img { max-width: 100%; height: auto; display: block; }
a { color: var(--teal); text-underline-offset: 0.15em; }
a:focus-visible { outline: 3px solid var(--teal); outline-offset: 3px; border-radius: 4px; }
h1, h2, h3 { font-family: "Archivo", system-ui, sans-serif; font-weight: 600;
  line-height: 1.2; letter-spacing: -0.01em; margin: 0; }
h1 { font-size: clamp(2rem, 5.5vw, 3.4rem); }
h2 { font-size: clamp(1.6rem, 3.5vw, 2.2rem); }
h3 { font-size: 1.15rem; }
p { margin: 0.6rem 0 0; }
strong { font-weight: 600; }
.largura { max-width: var(--largura); margin: 0 auto; padding: 0 1.25rem; }
.centro { text-align: center; }
.secundario { color: var(--tinta-secundaria); }
.lede { font-size: 1.15rem; color: var(--tinta-secundaria); max-width: 44rem; }
.centro .lede { margin-left: auto; margin-right: auto; }
.sobretitulo { display: inline-block; font-family: "Archivo", sans-serif; font-weight: 600;
  font-size: 0.85rem; letter-spacing: 0.08em; text-transform: uppercase;
  color: var(--teal); margin-bottom: 0.75rem; }
.botao { display: inline-flex; align-items: center; gap: 0.5rem; min-height: 48px;
  padding: 0.7rem 1.3rem; border-radius: 999px; font-weight: 600; text-decoration: none;
  border: 1px solid var(--teal); transition: background 0.15s, color 0.15s; }
.botao-cheio { background: var(--teal); color: #fff; }
.botao-cheio:hover { background: #0B3B34; }
.botao-vazado { background: transparent; color: var(--teal); }
.botao-vazado:hover { background: var(--teal-claro); }
.botao-pequeno { min-height: 40px; padding: 0.4rem 1rem; }

header { position: sticky; top: 0; z-index: 10; background: rgba(247, 246, 243, 0.92);
  backdrop-filter: blur(8px); border-bottom: 1px solid var(--borda); }
.navegacao { display: flex; align-items: center; justify-content: space-between;
  gap: 1rem; min-height: 64px; }
.marca { display: flex; align-items: center; gap: 0.6rem; color: var(--tinta);
  text-decoration: none; font-family: "Archivo", sans-serif; font-weight: 600; }
.marca img { height: 36px; width: auto; }
.navegacao nav { display: flex; align-items: center; gap: 1.25rem; flex-wrap: wrap;
  justify-content: flex-end; }
/* `:not(.botao)` porque esta regra é mais específica que .botao-cheio e
   apagaria o branco do rótulo sobre o teal. */
.navegacao nav a:not(.botao) { color: var(--tinta-secundaria); text-decoration: none;
  font-weight: 600; font-size: 0.95rem; }
.navegacao nav a:not(.botao):hover { color: var(--teal); }

/* Menu sanduíche: só no celular, onde os sete itens não cabem numa linha. */
.sanduiche { display: none; }
@media (max-width: 720px) {
  .navegacao { flex-wrap: nowrap; }
  .sanduiche { display: grid; place-content: center; gap: 5px;
    width: 48px; height: 48px; padding: 0; cursor: pointer;
    background: var(--superficie); border: 1px solid var(--borda);
    border-radius: 12px; }
  .sanduiche:focus-visible { outline: 3px solid var(--teal); outline-offset: 3px; }
  .sanduiche span { display: block; width: 22px; height: 2px; border-radius: 2px;
    background: var(--tinta); }
  /* As três barras viram um X quando o menu está aberto. */
  header.aberto .sanduiche span:nth-child(1) { transform: translateY(7px) rotate(45deg); }
  header.aberto .sanduiche span:nth-child(2) { opacity: 0; }
  header.aberto .sanduiche span:nth-child(3) { transform: translateY(-7px) rotate(-45deg); }

  /* O painel desce do cabeçalho e ocupa a largura da tela. */
  .navegacao nav { display: none; position: absolute; top: 100%; left: 0; right: 0;
    flex-direction: column; align-items: stretch; gap: 0;
    padding: 0.25rem 1.25rem 1.25rem; background: var(--superficie);
    border-bottom: 1px solid var(--borda);
    box-shadow: 0 20px 32px -24px rgba(20, 32, 30, 0.55); }
  header.aberto .navegacao nav { display: flex; }
  /* Dentro do painel cabem todos: nada fica escondido por falta de espaço. */
  .navegacao nav .discreto { display: block; }
  .navegacao nav a:not(.botao) { padding: 0.9rem 0; font-size: 1rem;
    color: var(--tinta); border-bottom: 1px solid var(--trilho); }
  .navegacao nav .botao { margin-top: 1.1rem; justify-content: center; }
}
@media (prefers-reduced-motion: no-preference) {
  .sanduiche span { transition: transform 0.18s ease, opacity 0.18s ease; }
}

.abertura { padding: 4rem 0 3rem; }
.abertura-grade { display: grid; grid-template-columns: 1.15fr 0.85fr; gap: 3rem;
  align-items: center; }
.abertura h1 span { color: var(--teal); }
.chamadas { display: flex; flex-wrap: wrap; gap: 0.75rem; margin-top: 1.75rem; }
.nota { font-size: 0.9rem; color: var(--tinta-secundaria); margin-top: 1rem; }
/* A captura precisa se destacar de um fundo quase branco, no tamanho da
   abertura e no da galeria. Três camadas: um contorno de 1 px que encosta na
   borda, uma sombra curta que define o recorte em qualquer tamanho e uma
   longa que dá profundidade. A sombra única e muito difusa que havia aqui
   funcionava só na abertura, onde a imagem é grande. */
.celular { border-radius: 28px; border: 1px solid var(--borda-captura);
  background: var(--superficie); overflow: hidden;
  box-shadow: 0 1px 2px rgba(20, 32, 30, 0.10),
              0 5px 12px -3px rgba(20, 32, 30, 0.16),
              0 20px 40px -20px rgba(20, 32, 30, 0.30); }
/* A captura é um botão: ampliar é a única coisa que ela faz. */
button.celular { display: block; width: 100%; padding: 0; cursor: zoom-in;
  font: inherit; color: inherit; transition: transform 0.15s, box-shadow 0.15s; }
button.celular:hover { transform: translateY(-2px);
  box-shadow: 0 1px 2px rgba(20, 32, 30, 0.10),
              0 8px 16px -4px rgba(20, 32, 30, 0.18),
              0 26px 48px -22px rgba(20, 32, 30, 0.34); }
button.celular:focus-visible { outline: 3px solid var(--teal); outline-offset: 4px; }

/* Ampliação da captura, como em loja virtual. Sem biblioteca: são trinta
   linhas de CSS e um script pequeno. */
.lupa { position: fixed; inset: 0; z-index: 50; background: rgba(10, 18, 16, 0.9);
  display: flex; align-items: center; justify-content: center; padding: 1rem; }
.lupa[hidden] { display: none; }
.lupa figure { margin: 0; display: flex; flex-direction: column; align-items: center;
  gap: 0.9rem; max-height: 100%; max-width: 100%; }
.lupa img { max-width: 100%; max-height: calc(100vh - 8rem);
  max-height: calc(100dvh - 8rem); width: auto; border-radius: 20px;
  border: 1px solid rgba(255, 255, 255, 0.14); background: var(--superficie); }
.lupa figcaption { color: #F3F2EE; font-size: 0.95rem; line-height: 1.4;
  text-align: center; max-width: 36rem; }
.lupa button { position: absolute; display: grid; place-items: center;
  width: 48px; height: 48px; border-radius: 999px; border: 0; cursor: pointer;
  background: rgba(255, 255, 255, 0.14); color: #fff; font-size: 1.6rem;
  line-height: 1; }
.lupa button:hover { background: rgba(255, 255, 255, 0.26); }
.lupa button:focus-visible { outline: 3px solid #fff; outline-offset: 3px; }
.lupa .fechar { top: 1rem; right: 1rem; }
.lupa .anterior { left: 1rem; top: 50%; transform: translateY(-50%); }
.lupa .seguinte { right: 1rem; top: 50%; transform: translateY(-50%); }
.lupa button[hidden] { display: none; }
@media (max-width: 720px) {
  .lupa { padding: 0.35rem; }
  /* Perto de 90% da altura da tela: é o que deixa o texto da interface
     legível na captura, que é o motivo de ampliar. */
  .lupa figure { gap: 0.5rem; }
  .lupa img { max-height: 86vh; max-height: 86dvh; }
  .lupa figcaption { font-size: 0.85rem; }
  .lupa .anterior { left: 0.25rem; }
  .lupa .seguinte { right: 0.25rem; }
}
@media (prefers-reduced-motion: no-preference) {
  .lupa { animation: surgir 0.18s ease-out; }
  .lupa img { animation: crescer 0.18s ease-out; }
}
@keyframes surgir { from { opacity: 0; } }
@keyframes crescer { from { transform: scale(0.97); } }
body.ampliando { overflow: hidden; }
.abertura .celular { max-width: 340px; margin: 0 auto; }
@media (max-width: 860px) {
  .abertura { padding: 2.5rem 0 2rem; }
  .abertura-grade { grid-template-columns: 1fr; gap: 2rem; }
  .abertura .celular { max-width: 280px; }
}

section { padding: 3.5rem 0; }
section + section { border-top: 1px solid var(--borda); }
.grade { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 1rem; margin-top: 2rem; }
.cartao { background: var(--superficie); border: 1px solid var(--borda);
  border-radius: var(--raio); padding: 1.5rem; }
.cartao .icone { width: 44px; height: 44px; border-radius: 12px; display: grid;
  place-items: center; background: var(--teal-claro); color: var(--sobre-teal-claro);
  margin-bottom: 1rem; }
.cartao .icone svg { width: 24px; height: 24px; }
.cartao p { color: var(--tinta-secundaria); font-size: 0.98rem; }

.retornos { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 1rem; margin-top: 2rem; }
.retorno { border-radius: var(--raio); padding: 1.25rem 1.5rem; font-weight: 600; }
.retorno small { display: block; font-weight: 400; margin-top: 0.25rem; }
.retorno-verde { background: var(--verde-fundo); color: var(--verde-texto); }
.retorno-laranja { background: var(--laranja-fundo); color: var(--laranja-texto); }
.retorno-vermelho { background: var(--vermelho-fundo); color: var(--vermelho-texto); }

.passos { list-style: none; counter-reset: passo; padding: 0; margin: 2rem 0 0;
  display: grid; gap: 1.25rem; }
.passo { display: grid; grid-template-columns: 56px 1fr 220px; gap: 1.25rem;
  align-items: center; background: var(--superficie); border: 1px solid var(--borda);
  border-radius: var(--raio); padding: 1.25rem; }
.passo::before { counter-increment: passo; content: counter(passo);
  font-family: "Archivo", sans-serif; font-weight: 600; font-size: 1.4rem;
  width: 56px; height: 56px; border-radius: 50%; display: grid; place-items: center;
  background: var(--teal); color: #fff; }
.passo p { color: var(--tinta-secundaria); font-size: 0.98rem; }
.passo .celular { max-width: 220px; border-radius: 20px; }
@media (max-width: 760px) {
  .passo { grid-template-columns: 48px 1fr; }
  .passo::before { width: 48px; height: 48px; font-size: 1.2rem; }
  .passo .celular { grid-column: 1 / -1; max-width: 240px; margin: 0 auto; }
}

.galeria { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1.25rem; margin-top: 2rem; }
.galeria figure { margin: 0; }
.galeria figcaption { font-size: 0.9rem; color: var(--tinta-secundaria);
  margin-top: 0.6rem; text-align: center; }
.galeria .celular { border-radius: 22px; }

.instalar ol { padding-left: 1.25rem; margin: 1rem 0 0; }
.instalar li { margin: 0.5rem 0; }
.instalar code { background: var(--trilho); padding: 0.1em 0.4em; border-radius: 6px;
  font-size: 0.92em; }
.duas-colunas { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; margin-top: 2rem; }
@media (max-width: 760px) { .duas-colunas { grid-template-columns: 1fr; } }

footer { border-top: 1px solid var(--borda); padding: 2.5rem 0 3rem;
  color: var(--tinta-secundaria); font-size: 0.92rem; }
footer .navegacao { min-height: 0; align-items: flex-start; }
footer nav a:not(.botao) { color: var(--tinta-secundaria); margin-left: 1.25rem; }

/* Páginas de texto (política, manual, reserva do link). */
.texto { max-width: 42rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
.texto h1 { font-size: 2rem; margin: 0 0 0.5rem; }
.texto h2 { font-size: 1.35rem; margin: 2.25rem 0 0.5rem; padding-top: 1.25rem;
  border-top: 1px solid var(--borda); }
.texto h3 { font-size: 1.1rem; margin: 1.75rem 0 0.25rem; }
.texto p, .texto ul { margin: 0.75rem 0; }
.texto li { margin: 0.35rem 0; }
.texto em:first-child:last-child { color: var(--tinta-secundaria); font-style: normal; }
.texto code { font-size: 0.9em; }
/* Vale nas duas formas de página de texto: a de coluna única e a do manual,
   que tem o cabeçalho fora da coluna de conteúdo. */
.texto .topo, .manual .topo { display: flex; align-items: center; gap: 0.75rem;
  margin-bottom: 2rem; color: var(--tinta); text-decoration: none;
  font-family: "Archivo", sans-serif; font-weight: 600; }
.texto .topo img, .manual .topo img { width: 40px; height: 40px;
  border-radius: 10px; }
.texto footer { border: 0; padding: 3rem 0 0; }
.trilha { font-size: 0.9rem; color: var(--tinta-secundaria); margin-bottom: 1.5rem; }
.trilha a { color: var(--tinta-secundaria); }

/* O manual é longo e consultado em campo: índice numa coluna à esquerda,
   texto à direita, e as capturas no tamanho de um celular, ampliáveis como na
   inicial. */
.manual { max-width: 74rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }
.manual-grade { display: grid; grid-template-columns: 17rem minmax(0, 1fr);
  gap: 3.5rem; align-items: start; }
.manual .conteudo { max-width: 44rem; margin: 0; padding: 0; }

/* Cola no alto ao rolar, e rola por dentro quando não couber. O topo
   acompanha a altura do cabeçalho fixo. */
.manual .indice { position: sticky; top: 5rem; max-height: calc(100vh - 7rem);
  overflow-y: auto; overscroll-behavior: contain;
  border-left: 2px solid var(--borda); padding: 0.25rem 0 0.25rem 1.25rem; }
.manual .indice summary { font-family: "Archivo", sans-serif; font-weight: 600;
  font-size: 0.85rem; letter-spacing: 0.08em; text-transform: uppercase;
  color: var(--teal); cursor: pointer; margin-bottom: 0.75rem; }
.manual .indice summary:focus-visible { outline: 3px solid var(--teal);
  outline-offset: 3px; border-radius: 4px; }
.manual .toc ul { list-style: none; margin: 0; padding: 0; }
.manual .toc ul ul { padding-left: 0.9rem; }
.manual .toc li { margin: 0.1rem 0; }
.manual .toc a { display: block; padding: 0.3rem 0; text-decoration: none;
  font-size: 0.95rem; line-height: 1.35; }
.manual .toc a:hover { text-decoration: underline; }
.manual .toc ul ul a { color: var(--tinta-secundaria); font-size: 0.9rem; }
/* A seção que está na tela, marcada enquanto se rola. */
.manual .toc a.atual { color: var(--teal); font-weight: 600; }
.manual .toc ul ul a.atual { color: var(--teal); }

/* Sob o cabeçalho fixo: sem isto, o link leva o título para debaixo dele. */
.manual h2, .manual h3 { scroll-margin-top: 5rem; }

@media (max-width: 900px) {
  .manual { padding-top: 1.5rem; }
  .manual-grade { grid-template-columns: 1fr; gap: 1.5rem; }
  .manual .indice { position: static; max-height: none; border-left: 0;
    padding: 1rem 1.25rem; background: var(--superficie);
    border: 1px solid var(--borda); border-radius: var(--raio); }
  .manual .indice summary { margin-bottom: 0; }
  .manual .indice[open] summary { margin-bottom: 0.75rem; }
}
.manual h3 { margin: 2rem 0 0.25rem; }
.manual table { border-collapse: collapse; width: 100%; margin: 1.25rem 0;
  font-size: 0.95rem; }
.manual th, .manual td { text-align: left; vertical-align: top;
  padding: 0.6rem 0.7rem; border-bottom: 1px solid var(--borda); }
.manual th { font-family: "Archivo", sans-serif; font-weight: 600;
  font-size: 0.85rem; letter-spacing: 0.04em; text-transform: uppercase;
  color: var(--tinta-secundaria); }
.manual blockquote { margin: 1.5rem 0; padding: 1rem 1.25rem;
  background: var(--teal-claro); color: var(--sobre-teal-claro);
  border-radius: var(--raio); }
.manual blockquote p { margin: 0.4rem 0 0; }
.manual blockquote p:first-child { margin-top: 0; }
.manual button.celular { max-width: 260px; margin: 1.75rem auto; }
.manual hr { border: 0; border-top: 1px solid var(--borda); margin: 3rem 0 2rem; }
@media (max-width: 560px) {
  .manual table { font-size: 0.9rem; }
  .manual th, .manual td { padding: 0.5rem 0.4rem; }
  .manual button.celular { max-width: 220px; }
}
"""

# Ícones das características, em linha para não depender de arquivo externo.
ICONES = {
    "offline": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 18a5 5 0 0 0-1-9.9A7 7 0 0 0 3 10a4 4 0 0 0 1 8h13z"/><path d="m3 3 18 18"/></svg>',
    "rede": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="7" height="12" rx="1.5"/><rect x="15" y="5" width="7" height="12" rx="1.5"/><path d="M9 13h6"/></svg>',
    "som": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5 6 9H2v6h4l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M19 5.5a9 9 0 0 1 0 13"/></svg>',
    "config": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h10M18 6h2M4 12h2M10 12h10M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="8" cy="12" r="2"/><circle cx="18" cy="18" r="2"/></svg>',
    "conflito": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7h13l-3-3M21 17H8l3 3"/><path d="M12 11v2M12 16h.01"/></svg>',
    "relatorio": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/></svg>',
}


# Ampliação das capturas. Sem biblioteca: a página é estática, e isto é o que
# uma loja virtual faz — clicar na imagem e vê-la grande sobre fundo escuro.
#
# Os cuidados que não se veem: o foco volta para a captura de origem ao
# fechar, fica preso dentro do diálogo enquanto ele está aberto, e o gesto de
# voltar do Android fecha a ampliação em vez de sair da página. Sem isso, quem
# usa teclado ou leitor de tela fica preso atrás do fundo escurecido.
SCRIPT_LUPA = """<script>
(function () {
  var gatilhos = [].slice.call(document.querySelectorAll('.ampliar'));
  if (!gatilhos.length) return;

  var lupa = document.createElement('div');
  lupa.className = 'lupa';
  lupa.hidden = true;
  lupa.setAttribute('role', 'dialog');
  lupa.setAttribute('aria-modal', 'true');
  lupa.setAttribute('aria-label', 'Captura ampliada');
  lupa.innerHTML =
    '<button type="button" class="fechar" aria-label="Fechar">×</button>' +
    '<button type="button" class="anterior" aria-label="Captura anterior">‹</button>' +
    '<figure><img alt=""><figcaption></figcaption></figure>' +
    '<button type="button" class="seguinte" aria-label="Próxima captura">›</button>';
  document.body.appendChild(lupa);

  var imagem = lupa.querySelector('img');
  var legenda = lupa.querySelector('figcaption');
  var fechar = lupa.querySelector('.fechar');
  var anterior = lupa.querySelector('.anterior');
  var seguinte = lupa.querySelector('.seguinte');

  var origem = null;
  var irmaos = [];
  var atual = 0;
  var empurrou = false;

  function mostrar(i) {
    atual = (i + irmaos.length) % irmaos.length;
    var img = irmaos[atual].querySelector('img');
    imagem.src = img.src;
    imagem.alt = img.alt;
    legenda.textContent = img.alt;
    var varias = irmaos.length > 1;
    anterior.hidden = !varias;
    seguinte.hidden = !varias;
  }

  function abrir(gatilho) {
    origem = gatilho;
    irmaos = gatilhos.filter(function (g) {
      return g.dataset.grupo === gatilho.dataset.grupo;
    });
    mostrar(irmaos.indexOf(gatilho));
    lupa.hidden = false;
    document.body.classList.add('ampliando');
    fechar.focus();
    // O gesto de voltar fecha a ampliação, e não a página.
    try {
      history.pushState({ lupa: true }, '');
      empurrou = true;
    } catch (e) { empurrou = false; }
  }

  function encerrar(voltando) {
    if (lupa.hidden) return;
    lupa.hidden = true;
    imagem.removeAttribute('src');
    document.body.classList.remove('ampliando');
    // Volta o foco para a captura que estava sendo vista, que pode não ser a
    // de onde se partiu: quem andou com as setas continua de onde parou.
    var alvo = irmaos[atual] || origem;
    if (alvo) alvo.focus();
    origem = null;
    if (empurrou && !voltando) history.back();
    empurrou = false;
  }

  gatilhos.forEach(function (g) {
    g.addEventListener('click', function () { abrir(g); });
  });

  fechar.addEventListener('click', function () { encerrar(false); });
  anterior.addEventListener('click', function () { mostrar(atual - 1); });
  seguinte.addEventListener('click', function () { mostrar(atual + 1); });
  lupa.addEventListener('click', function (e) {
    // Clique fora da imagem e dos botões fecha.
    if (e.target === lupa || e.target.tagName === 'FIGURE') encerrar(false);
  });
  window.addEventListener('popstate', function () { encerrar(true); });

  document.addEventListener('keydown', function (e) {
    if (lupa.hidden) return;
    if (e.key === 'Escape') { encerrar(false); return; }
    if (e.key === 'ArrowLeft' && irmaos.length > 1) { mostrar(atual - 1); return; }
    if (e.key === 'ArrowRight' && irmaos.length > 1) { mostrar(atual + 1); return; }
    if (e.key !== 'Tab') return;
    // Foco preso no diálogo enquanto ele estiver aberto.
    var focaveis = [fechar, anterior, seguinte].filter(function (b) {
      return !b.hidden;
    });
    var i = focaveis.indexOf(document.activeElement);
    e.preventDefault();
    var proximo = e.shiftKey ? i - 1 : i + 1;
    focaveis[(proximo + focaveis.length) % focaveis.length].focus();
  });
})();
</script>"""


# O índice acompanha a leitura: o item da seção visível fica marcado. Sem isso,
# num texto longo, o índice diz para onde ir mas não diz onde se está.
#
# No celular ele nasce recolhido — trinta e quatro links antes do texto seriam
# trinta e quatro linhas de rolagem até começar a ler — e um toque no título
# abre.
SCRIPT_INDICE = """<script>
(function () {
  var indice = document.querySelector('.indice');
  if (!indice) return;

  if (window.matchMedia('(max-width: 900px)').matches) indice.open = false;

  var links = {};
  [].forEach.call(indice.querySelectorAll('a[href^="#"]'), function (a) {
    links[decodeURIComponent(a.getAttribute('href').slice(1))] = a;
  });

  var titulos = [].filter.call(
    document.querySelectorAll('.conteudo h2, .conteudo h3'),
    function (h) { return links[h.id]; }
  );
  if (!titulos.length || !window.IntersectionObserver) return;

  var visiveis = new Set();
  function marcar() {
    var atual = null;
    for (var i = 0; i < titulos.length; i++) {
      if (visiveis.has(titulos[i].id)) { atual = titulos[i].id; break; }
    }
    // Nenhum título na tela: vale o último que passou por cima.
    if (!atual) {
      for (var j = titulos.length - 1; j >= 0; j--) {
        if (titulos[j].getBoundingClientRect().top < 120) {
          atual = titulos[j].id;
          break;
        }
      }
    }
    for (var id in links) links[id].classList.toggle('atual', id === atual);
  }

  var observador = new IntersectionObserver(function (entradas) {
    entradas.forEach(function (e) {
      if (e.isIntersecting) visiveis.add(e.target.id);
      else visiveis.delete(e.target.id);
    });
    marcar();
  }, { rootMargin: '-80px 0px -70% 0px' });

  titulos.forEach(function (h) { observador.observe(h); });
  marcar();
})();
</script>"""


# O menu do celular. Um botão que revela, e nada mais: fecha pela tecla Esc,
# pelo toque fora, e ao escolher um item — que na página inicial leva a uma
# seção logo abaixo, e deixar o painel cobrindo o destino seria estranho.
SCRIPT_MENU = """<script>
(function () {
  var cabecalho = document.querySelector('header');
  var botao = cabecalho && cabecalho.querySelector('.sanduiche');
  var menu = document.getElementById('menu');
  if (!botao || !menu) return;

  function abrir(sim) {
    cabecalho.classList.toggle('aberto', sim);
    botao.setAttribute('aria-expanded', sim ? 'true' : 'false');
    botao.setAttribute('aria-label', sim ? 'Fechar o menu' : 'Abrir o menu');
  }

  botao.addEventListener('click', function () {
    var abrindo = botao.getAttribute('aria-expanded') !== 'true';
    abrir(abrindo);
    if (abrindo) {
      var primeiro = menu.querySelector('a');
      if (primeiro) primeiro.focus();
    }
  });

  menu.addEventListener('click', function (e) {
    if (e.target.closest('a')) abrir(false);
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && cabecalho.classList.contains('aberto')) {
      abrir(false);
      botao.focus();
    }
  });

  document.addEventListener('click', function (e) {
    if (!cabecalho.contains(e.target)) abrir(false);
  });

  // Voltando à largura de computador, o painel não fica preso aberto.
  var largo = window.matchMedia('(min-width: 721px)');
  var aoMudar = function (e) { if (e.matches) abrir(false); };
  if (largo.addEventListener) largo.addEventListener('change', aoMudar);
  else largo.addListener(aoMudar);
})();
</script>"""


def estilo(prefixo: str) -> str:
    faces = "\n".join(
        f'@font-face {{ font-family: "{familia}"; font-weight: {peso}; '
        f'font-display: swap; src: url("{prefixo}fontes/{arquivo}") format("truetype"); }}'
        for arquivo, (familia, peso) in FONTES.items()
    )
    return ESTILO.replace("FONTES", faces)


def pagina(titulo: str, descricao: str, corpo: str, prefixo: str = "") -> str:
    """Página completa. `prefixo` leva da página à raiz do site: os caminhos
    são relativos, e o site funciona sob qualquer endereço."""
    return f"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(titulo)}</title>
<meta name="description" content="{html.escape(descricao)}">
<meta property="og:title" content="{html.escape(titulo)}">
<meta property="og:description" content="{html.escape(descricao)}">
<meta property="og:image" content="{SITE}imagens/painel.png">
<link rel="icon" href="{prefixo}icone.png">
<style>{estilo(prefixo)}</style>
</head>
<body>
{corpo}
</body>
</html>
"""


def converter(
    texto: str,
    locais: dict[str, str] | None = None,
    profundidade: str = "2-6",
) -> str:
    """Markdown para HTML, com tabelas e índice."""
    return converter_com_indice(texto, locais, profundidade)[0]


def converter_com_indice(
    texto: str,
    locais: dict[str, str] | None = None,
    profundidade: str = "2-6",
) -> tuple[str, str]:
    """Markdown para (corpo, índice), cada um por sua conta.

    Separados porque o manual põe o índice numa coluna própria, ao lado do
    texto, e não no meio dele. O conversor monta os dois de qualquer forma —
    o `[TOC]` no Markdown só dizia onde encaixar, e fora daqui, no GitHub,
    aparecia como texto solto.

    `locais` traduz links para documentos que **também** existem no site
    (`privacidade.md` → `../privacidade/`). O que não estiver ali aponta para o
    arquivo no GitHub: é onde ele existe.

    `profundidade` limita o que entra no índice. O título da página fica de
    fora sempre — um índice cujo primeiro item é o nome do documento aninha
    tudo um nível sem dizer nada.
    """
    conversor = markdown.Markdown(
        extensions=["tables", "toc"],
        extension_configs={
            "toc": {"slugify": slugify_unicode, "toc_depth": profundidade}
        },
        output_format="html",
    )
    corpo = conversor.convert(texto)
    traducao = locais or {}

    def apontar(html_convertido: str) -> str:
        return re.sub(
            r'href="(?!https?:|#|mailto:)([^"]+\.md)(#[^"]*)?"',
            lambda m: 'href="{}{}"'.format(
                traducao.get(
                    m.group(1), f"{REPOSITORIO}/blob/main/docs/{m.group(1)}"
                ),
                m.group(2) or "",
            ),
            html_convertido,
        )

    return apontar(corpo), conversor.toc


def capturas_ampliaveis(corpo: str, prefixo: str) -> str:
    """Transforma as imagens de um texto convertido em capturas ampliáveis.

    O manual é consultado em campo, muitas vezes no mesmo celular que está
    levantando: ver a tela em tamanho maior é a diferença entre reconhecer o
    botão e não reconhecer. Usa a mesma peça da página inicial.
    """
    return re.sub(
        r'<p><img alt="([^"]*)" src="imagens/([^"]+)"\s*/?></p>',
        lambda m: (
            f'<button type="button" class="celular ampliar" data-grupo="manual" '
            f'aria-label="Ampliar: {m.group(1)}">'
            f'<img src="{prefixo}imagens/{m.group(2)}" alt="{m.group(1)}" '
            f'width="720" height="1603" loading="lazy"></button>'
        ),
        corpo,
    )


def captura(nome: str, grupo: str, carregamento: str = "lazy") -> str:
    """Uma captura de tela, clicável para ampliar.

    É um `<button>`, e não uma `<div>` com `onclick`: ampliar é uma ação, e
    assim ela chega pelo teclado e pelo leitor de tela sem nada a mais.
    `grupo` liga as capturas que as setas percorrem — a galeria não navega
    para os passos, que contam outra história.

    720 × 1603 é o que tool/reduzir_capturas.py produz. A ampliação ajusta
    pela altura da janela, que é sempre menor que 1603 px: a imagem nunca é
    esticada além do original, e por isso a resolução atual basta.
    """
    alt = html.escape(CAPTURAS[nome])
    return (
        f'<button type="button" class="celular ampliar" data-grupo="{grupo}" '
        f'aria-label="Ampliar: {alt}">'
        f'<img src="imagens/{nome}.png" alt="{alt}" '
        f'width="720" height="1603" loading="{carregamento}"></button>'
    )


def cabecalho(logo: str) -> str:
    """A barra do topo.

    No celular ela não cabe: com sete itens, quebrava em duas linhas e os
    primeiros links iam parar acima da logomarca. Ali os links ficam atrás do
    botão sanduíche, que é o gesto que todo mundo já conhece.
    """
    return f"""<header>
<div class="largura navegacao">
<a class="marca" href="#inicio"><img src="{logo}" alt="SLAP Mobile"></a>
<button type="button" class="sanduiche" aria-expanded="false" aria-controls="menu"
 aria-label="Abrir o menu"><span></span><span></span><span></span></button>
<nav id="menu">
<a class="discreto" href="#por-que">Por quê</a>
<a class="discreto" href="#como-usar">Como usar</a>
<a class="discreto" href="#capturas">Capturas</a>
<a href="manual/">Manual</a>
<a href="#instalar">Instalar</a>
<a class="discreto" href="{REPOSITORIO}">GitHub</a>
<a class="botao botao-cheio botao-pequeno" href="{RELEASE}">Baixar o APK</a>
</nav>
</div>
</header>"""


def abertura() -> str:
    return f"""<section class="abertura" id="inicio">
<div class="largura abertura-grade">
<div>
<span class="sobretitulo">Software livre para o inventário do IFPI</span>
<h1>Inventário patrimonial <span>sem internet e sem servidor.</span></h1>
<p class="lede">Cada celular carrega o inventário inteiro, funciona sozinho e sincroniza
direto com os outros pela rede Wi-Fi local. Leia os códigos de barras, ouça o resultado e
exporte os relatórios prontos para o SUAP.</p>
<div class="chamadas">
<a class="botao botao-cheio" href="{RELEASE}">Baixar o APK</a>
<a class="botao botao-vazado" href="{REPOSITORIO}">Ver o código no GitHub</a>
</div>
<p class="nota">Software livre · Apache-2.0 · Android 7.0 ou mais novo · sem conta, sem anúncios</p>
</div>
{captura("levantamento", "abertura", carregamento="eager")}
</div>
</section>"""


def por_que() -> str:
    cartoes = [
        ("offline", "Funciona sem rede",
         "Sem servidor, sem conta e sem internet. Importe a planilha exportada do SUAP "
         "e comece a levantar — dentro do almoxarifado, no subsolo ou no campus sem sinal."),
        ("rede", "Sincroniza entre os celulares",
         "Os aparelhos do mesmo inventário trocam o que cada um levantou, direto entre "
         "eles, pela rede Wi-Fi local. Não há aparelho principal: todos têm a cópia inteira."),
        ("som", "Três retornos, sem olhar a tela",
         "Cada leitura responde com som, vibração, cor e texto próprios. O bipe já diz se o "
         "item entrou, se já tinha sido lido ou se não está na planilha — não é preciso "
         "conferir a tela a cada patrimônio."),
        ("config", "Configure uma vez, leia dezenas",
         "Sala, responsável, estado de conservação e situação de uso valem para as "
         "próximas leituras, até você mudar. É de onde vem a velocidade."),
        ("conflito", "Nada se perde em silêncio",
         "Duas pessoas alteraram o mesmo item sem sincronizar? O aplicativo mostra o "
         "conflito para alguém decidir, e a decisão vale em todos os aparelhos."),
        ("relatorio", "Relatórios prontos",
         "Itens corretos, itens que precisam de atualização no SUAP e itens não "
         "localizados, em XLSX ou CSV. Depois de sincronizar, saem iguais em qualquer "
         "aparelho do inventário."),
    ]
    grade = "\n".join(
        f'<div class="cartao"><div class="icone">{ICONES[icone]}</div>'
        f"<h3>{titulo}</h3><p>{texto}</p></div>"
        for icone, titulo, texto in cartoes
    )
    return f"""<section id="por-que">
<div class="largura centro">
<span class="sobretitulo">Por quê</span>
<h2>Feito para o levantamento em campo</h2>
<p class="lede">O sistema anterior dependia de um servidor e do navegador: sem rede, sem
inventário. Aqui o celular é o inventário.</p>
<div class="grade">
{grade}
</div>
<div class="retornos">
<div class="retorno retorno-verde">Registrado<small>encontrado e gravado com a configuração atual</small></div>
<div class="retorno retorno-laranja">Já verificado<small>lido antes; nada é sobrescrito sem confirmação</small></div>
<div class="retorno retorno-vermelho">Não localizado<small>o código lido não está na planilha deste inventário</small></div>
</div>
</div>
</section>"""


def como_usar() -> str:
    passos = [
        ("identidade", "Identifique-se",
         "Nome e matrícula, sem senha. Ficam no aparelho e acompanham cada patrimônio que "
         "você verificar, para o relatório dizer quem conferiu o quê."),
        ("importacao", "Crie o inventário e importe a planilha do SUAP",
         "XLSX ou CSV, como sai da exportação. As colunas são reconhecidas pelo nome e você "
         "confere o resultado antes de importar. Importar de novo acrescenta; nunca apaga o "
         "que já foi levantado."),
        ("compartilhar", "Chame os colegas",
         "Toque em Compartilhar e mostre o QR code ou envie o link. No outro celular, "
         "Novo → Ler o QR code de outro aparelho. Você aceita cada pedido de entrada; os dois "
         "precisam estar na mesma rede Wi-Fi."),
        ("configuracao", "Configure as leituras",
         "Sala, responsável, estado de conservação e situação de uso. A configuração vale "
         "para todas as leituras seguintes, até você mudar — trocar de sala é só um dos "
         "motivos para mudá-la."),
        ("levantamento", "Leia os códigos",
         "Pela câmera, com um leitor externo ou digitando o tombo. Verde é registrado, "
         "laranja é já verificado, vermelho é não localizado — com som e vibração para cada um."),
        ("sincronizacao", "Troque os dados quando quiser",
         "A troca é nos dois sentidos: cada aparelho manda o que levantou e recebe o que o "
         "outro levantou. Eles se encontram sozinhos na mesma rede; se a rede da instituição "
         "isolar os aparelhos, use o ponto de acesso de um dos celulares. Havendo conflito, "
         "ele aparece para alguém decidir, e a decisão vale para todos."),
        ("relatorios", "Confira e exporte",
         "Três grupos: o que está certo, o que precisa de atualização no SUAP e o que não "
         "foi localizado. Cada um sai em XLSX ou CSV. São eles que alimentam o relatório "
         "final do inventário, que é arquivado, e o que vai ao setor de patrimônio para "
         "atualizar o SUAP."),
    ]
    lista = "\n".join(
        f'<li class="passo"><div><h3>{titulo}</h3><p>{texto}</p></div>'
        f'{captura(nome, "passos")}</li>'
        for nome, titulo, texto in passos
    )
    return f"""<section id="como-usar">
<div class="largura">
<div class="centro">
<span class="sobretitulo">Como usar</span>
<h2>Do arquivo do SUAP ao relatório, em sete passos</h2>
<p class="lede">Uma pessoa importa; as outras entram pelo QR code ou pelo link. Cada uma
levanta uma sala. No fim, os relatórios são os mesmos em todos os aparelhos.</p>
</div>
<ol class="passos">
{lista}
</ol>
<p class="centro" style="margin-top:2rem">
<a class="botao botao-vazado" href="manual/">Ler o manual completo</a>
</p>
<p class="centro secundario">Cada tela em detalhe, com o que fazer em cada caso — inclusive
quando algo dá errado.</p>
</div>
</section>"""


def capturas() -> str:
    nomes = [
        "inventarios",
        "painel",
        "camera",
        "itens",
        "filtros",
        "detalhe",
    ]
    figuras = "\n".join(
        f'<figure>{captura(nome, "galeria")}'
        f"<figcaption>{html.escape(CAPTURAS[nome])}</figcaption></figure>"
        for nome in nomes
    )
    return f"""<section id="capturas">
<div class="largura centro">
<span class="sobretitulo">Capturas</span>
<h2>O aplicativo por dentro</h2>
<p class="lede">Tema claro e escuro, TalkBack e fonte ampliada. Toque em qualquer captura
para vê-la em tamanho maior.</p>
<div class="galeria">
{figuras}
</div>
</div>
</section>"""


def instalar() -> str:
    return f"""<section id="instalar" class="instalar">
<div class="largura">
<div class="centro">
<span class="sobretitulo">Instalar</span>
<h2>Um arquivo, nenhum cadastro</h2>
<p class="lede">Enquanto o aplicativo não está na Play Store, ele é instalado pelo APK
publicado no GitHub. Precisa de Android 7.0 ou mais novo.</p>
</div>
<div class="duas-colunas">
<div class="cartao">
<h3>No celular</h3>
<ol>
<li>Abra a <a href="{RELEASE}">versão mais recente</a> e baixe o arquivo
<code>.apk</code>. É um só, e serve a qualquer celular Android.</li>
<li>Ao abrir o arquivo, o Android pede permissão para instalar de fonte desconhecida:
toque em <strong>Configurações</strong>, ative <strong>Permitir desta fonte</strong> e volte.</li>
<li>Toque em <strong>Instalar</strong>. Na primeira abertura, informe seu nome e comece.</li>
</ol>
<p class="secundario">Para atualizar, instale o APK novo por cima: os inventários ficam.</p>
<p class="secundario">A partir de 30 de setembro de 2026, celular Android certificado no Brasil só
instala aplicativo de desenvolvedor registrado no Google. As versões publicadas aqui atendem a
isso. O passo a passo completo, com a conferência do arquivo, está em
<a href="{REPOSITORIO}/blob/main/docs/instalacao.md">docs/instalacao.md</a>.</p>
</div>
<div class="cartao">
<h3>Privacidade</h3>
<p>Sem conta, sem servidor e sem anúncios. Os dados do inventário ficam no aparelho e só
trafegam, cifrados, entre os celulares do mesmo inventário, pela rede local. A cópia de
segurança é um arquivo que você guarda onde quiser.</p>
<p>A leitura de códigos usa uma biblioteca do Google que envia a ele diagnósticos do
próprio funcionamento; nenhuma foto, código lido ou dado do inventário sai do aparelho.</p>
<p><a class="botao botao-vazado botao-pequeno" href="privacidade/">Ler a política de privacidade</a></p>
</div>
</div>
</div>
</section>"""


def rodape() -> str:
    return f"""<footer>
<div class="largura navegacao">
<div>SLAP Mobile · software livre sob a licença Apache-2.0<br>
Feito para o inventário patrimonial do Instituto Federal do Piauí.</div>
<nav>
<a href="{REPOSITORIO}">Código-fonte</a>
<a href="{REPOSITORIO}/issues">Issues</a>
<a href="privacidade/">Privacidade</a>
</nav>
</div>
</footer>"""


def pagina_inicial(logo: str) -> str:
    return pagina(
        "SLAP Mobile — inventário patrimonial sem internet",
        "Inventário patrimonial offline e distribuído: cada celular carrega os dados, "
        "funciona sozinho e sincroniza com os outros pela rede local, sem servidor.",
        "\n".join([
            cabecalho(logo),
            "<main>",
            abertura(),
            por_que(),
            como_usar(),
            capturas(),
            instalar(),
            "</main>",
            rodape(),
            SCRIPT_LUPA,
            SCRIPT_MENU,
        ]),
    )


def pagina_politica() -> str:
    texto = FONTE_POLITICA.read_text(encoding="utf-8")
    titulo = re.search(r"^# (.+)$", texto, re.MULTILINE).group(1).strip()
    topo = '<a class="topo" href="../"><img src="../icone.png" alt="">SLAP Mobile</a>'
    rodape_politica = (
        f'<footer>Fonte: <a href="{REPOSITORIO}/blob/main/docs/privacidade.md">'
        "docs/privacidade.md</a> no repositório.</footer>"
    )
    return pagina(
        titulo,
        "Quais dados o SLAP Mobile guarda, para onde vão e por quê.",
        f'<main class="texto">{topo}{converter(texto)}{rodape_politica}</main>',
        prefixo="../",
    )


def pagina_manual() -> str:
    """O manual completo, de docs/manual.md.

    Página própria, e não mais uma seção da inicial: a inicial serve para
    decidir se vale usar o aplicativo; o manual, para conduzir o inventário.
    """
    texto = FONTE_MANUAL.read_text(encoding="utf-8")
    titulo = re.search(r"^# (.+)$", texto, re.MULTILINE).group(1).strip()
    trilha = (
        '<nav class="trilha" aria-label="Você está em">'
        '<a href="../">Início</a> <span aria-hidden="true">›</span> '
        "<span>Manual</span></nav>"
    )
    topo = '<a class="topo" href="../"><img src="../icone.png" alt="">SLAP Mobile</a>'
    bruto, indice = converter_com_indice(
        texto,
        locais={"privacidade.md": "../privacidade/"},
        profundidade="2-3",
    )
    corpo = capturas_ampliaveis(bruto, prefixo="../")

    # O índice fica numa coluna à esquerda, como em documentação — e recolhido
    # atrás de um toque no celular, onde trinta e quatro links antes do texto
    # seriam trinta e quatro linhas de rolagem até começar a ler.
    lado = (
        '<details class="indice" open>'
        "<summary>Neste manual</summary>"
        f'<nav aria-label="Índice do manual">{indice}</nav>'
        "</details>"
    )
    rodape_manual = (
        f'<footer>Fonte: <a href="{REPOSITORIO}/blob/main/docs/manual.md">'
        "docs/manual.md</a> no repositório. Encontrou algo errado ou faltando? "
        f'<a href="{REPOSITORIO}/issues">Abra uma issue</a>.</footer>'
    )
    return pagina(
        f"{titulo} — SLAP Mobile",
        "Como conduzir um inventário patrimonial com o SLAP Mobile, tela a "
        "tela: importar a planilha, levantar, trocar dados e exportar os "
        "relatórios.",
        f'<main class="manual">{topo}{trilha}'
        f'<div class="manual-grade">{lado}'
        f'<article class="texto conteudo">{corpo}{rodape_manual}</article>'
        "</div></main>" + SCRIPT_LUPA + SCRIPT_INDICE,
        prefixo="../",
    )


def pagina_entrar() -> str:
    """Reserva do link de entrada num inventário.

    Com o aplicativo instalado e o App Link verificado, o Android abre o
    aplicativo direto e esta página nunca aparece. Sem o aplicativo, ela
    explica o que o link é e oferece o APK; os dados do convite ficam no
    fragmento da URL, que o navegador não envia a servidor nenhum.
    """
    topo = '<a class="topo" href="../"><img src="../icone.png" alt="">SLAP Mobile</a>'
    # O nome do inventário vem no fragmento da URL, que o navegador não envia a
    # servidor nenhum. Escrito com textContent: é texto de quem mandou o link,
    # nunca marcação.
    script = """<script>
(function () {
  var bruto = location.hash.replace(/^#/, '');
  if (!bruto) return;
  var campos = {};
  bruto.split('&').forEach(function (par) {
    var i = par.indexOf('=');
    if (i < 0) return;
    try {
      campos[par.slice(0, i)] = decodeURIComponent(par.slice(i + 1).replace(/\\+/g, ' '));
    } catch (e) { /* percentual malformado: ignora o campo */ }
  });
  if (!campos.n) return;
  var alvo = document.getElementById('convite');
  alvo.textContent = campos.a ? campos.n + ' · ' + campos.a : campos.n;
  alvo.hidden = false;
})();
</script>"""
    corpo = f"""<main class="texto">{topo}
<h1>Convite para um inventário</h1>
<p id="convite" class="lede" hidden></p>
<p>Este link abre um inventário no SLAP Mobile, o aplicativo de inventário patrimonial
que funciona sem internet. Quem enviou o link vai aceitar sua entrada no aparelho dele; os
dois celulares precisam estar na mesma rede Wi-Fi.</p>
<h2>O aplicativo não abriu?</h2>
<ol>
<li>Instale o SLAP Mobile: <a class="botao botao-cheio botao-pequeno" href="{RELEASE}">Baixar o APK</a></li>
<li>Abra o aplicativo uma vez e informe seu nome.</li>
<li>Toque no link de novo. Se o Android perguntar com o que abrir, escolha o SLAP Mobile.</li>
</ol>
<p><em>O convite não contém a chave do inventário: ele só identifica o inventário e o
aparelho de quem convidou. A chave é entregue depois que a pessoa aceita o pedido.</em></p>
<footer>Como instalar fora da loja: <a href="{REPOSITORIO}/blob/main/docs/instalacao.md">docs/instalacao.md</a>.</footer>
</main>
{script}"""
    return pagina(
        "Convite para um inventário — SLAP Mobile",
        "Este link abre um inventário no SLAP Mobile. Instale o aplicativo e toque no link de novo.",
        corpo,
        prefixo="../",
    )


def impressao_digital() -> str | None:
    """A impressão digital SHA-256 da chave de release, se estiver disponível.

    Vem do ambiente (o workflow a injeta de um segredo) ou de um arquivo local,
    que fica fora do repositório. Um valor malformado é recusado em vez de
    gerar um assetlinks.json inválido, que faria o Android desistir da
    verificação sem dizer por quê.
    """
    bruto = os.environ.get("SLAP_IMPRESSAO_DIGITAL")
    if not bruto and FONTE_IMPRESSAO.exists():
        bruto = FONTE_IMPRESSAO.read_text(encoding="utf-8")

    if not bruto:
        return None

    valor = bruto.strip().upper()
    if not IMPRESSAO_DIGITAL.match(valor):
        print(
            "Aviso: impressão digital malformada, o assetlinks.json não será "
            "gerado. Esperado: 32 pares hexadecimais separados por dois-pontos.",
            file=sys.stderr,
        )
        return None
    return valor


def gravar_assetlinks(saida: Path) -> bool:
    """O arquivo que autoriza o aplicativo a abrir os links deste domínio.

    Sem ele o convite continua funcionando: o Android mostra o seletor de
    aplicativos em vez de abrir o SLAP Mobile direto.
    """
    digital = impressao_digital()
    if digital is None:
        return False

    conteudo = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": PACOTE_ANDROID,
                "sha256_cert_fingerprints": [digital],
            },
        }
    ]
    pasta = saida / ".well-known"
    pasta.mkdir(parents=True, exist_ok=True)
    (pasta / "assetlinks.json").write_text(
        json.dumps(conteudo, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return True


def gerar(saida: Path) -> None:
    if saida.exists():
        shutil.rmtree(saida)
    for pasta in ("privacidade", "manual", "entrar", "fontes", "imagens", "marca"):
        (saida / pasta).mkdir(parents=True)

    for arquivo in FONTES:
        shutil.copy(RAIZ / "assets" / "fontes" / arquivo, saida / "fontes" / arquivo)
    shutil.copy(RAIZ / "docs" / "loja" / "icone-512.png", saida / "icone.png")

    faltando = []
    for nome in CAPTURAS:
        origem = PASTA_IMAGENS / f"{nome}.png"
        if origem.exists():
            shutil.copy(origem, saida / "imagens" / f"{nome}.png")
        else:
            faltando.append(f"docs/imagens/{nome}.png")

    logo = "icone.png"
    if (PASTA_MARCA / LOGO).exists():
        shutil.copy(PASTA_MARCA / LOGO, saida / "marca" / LOGO)
        logo = f"marca/{LOGO}"
    else:
        faltando.append(f"docs/marca/{LOGO}")

    (saida / "index.html").write_text(pagina_inicial(logo), encoding="utf-8")
    (saida / "privacidade" / "index.html").write_text(pagina_politica(), encoding="utf-8")
    (saida / "manual" / "index.html").write_text(pagina_manual(), encoding="utf-8")
    (saida / "entrar" / "index.html").write_text(pagina_entrar(), encoding="utf-8")

    if not gravar_assetlinks(saida):
        print(
            "Aviso: sem a impressão digital da chave de release, o site sai sem "
            ".well-known/assetlinks.json. O convite continua funcionando, mas o "
            "Android vai oferecer o seletor de aplicativos em vez de abrir o "
            "SLAP Mobile direto. Ver o cabeçalho deste script.",
            file=sys.stderr,
        )

    if faltando:
        print("Aviso: imagens ausentes, o site sai com espaços vazios:", file=sys.stderr)
        for f in faltando:
            print(f"  {f}", file=sys.stderr)


if __name__ == "__main__":
    gerar(Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / "_site")
