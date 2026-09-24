#!/usr/bin/env python3
"""Gera o site estático publicado no GitHub Pages.

As lojas pedem a política de privacidade numa URL estável. A fonte da verdade
é docs/privacidade.md; este script só a converte para HTML, com a paleta e as
fontes do aplicativo, para a página publicada nunca divergir do texto versionado.

    python3 tool/gerar_site.py [pasta de saída, padrão _site]

Saída:
    index.html              apresentação curta, com os links
    privacidade/index.html  a política
    fontes/, icone.png      o que as páginas usam

Depende do pacote `markdown` (pip install markdown).
"""

import html
import re
import shutil
import sys
from pathlib import Path

import markdown
from markdown.extensions.toc import slugify_unicode

RAIZ = Path(__file__).resolve().parent.parent
REPOSITORIO = "https://github.com/guilhermefeitosa66/slap-mobile"

# docs/privacidade.md e o que ele cita por caminho relativo.
FONTE_POLITICA = RAIZ / "docs" / "privacidade.md"

FONTES = {
    "Archivo-SemiBold.ttf": ("Archivo", 600),
    "PublicSans-Regular.ttf": ("Public Sans", 400),
    "PublicSans-SemiBold.ttf": ("Public Sans", 600),
}

# Mesmos tokens de lib/app/tema.dart (PaletaClara / PaletaEscura).
ESTILO = """
:root {
  color-scheme: light dark;
  --fundo: #F7F6F3; --superficie: #FFFFFF; --tinta: #14201E;
  --tinta-secundaria: #55625F; --teal: #0F5C52; --teal-claro: #DCE9E6;
  --borda: #E2E0DA;
}
@media (prefers-color-scheme: dark) {
  :root {
    --fundo: #111816; --superficie: #1A2220; --tinta: #E9EDEB;
    --tinta-secundaria: #A9B5B2; --teal: #8FCFC2; --teal-claro: #1E3A35;
    --borda: #2C3633;
  }
}
FONTES
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--fundo); color: var(--tinta);
  font: 400 17px/1.6 "Public Sans", system-ui, sans-serif;
  -webkit-text-size-adjust: 100%;
}
main { max-width: 42rem; margin: 0 auto; padding: 2.5rem 1rem 4rem; }
h1, h2, h3 { font-family: "Archivo", system-ui, sans-serif; font-weight: 600;
  line-height: 1.25; word-spacing: 0.08em; }
h1 { font-size: 2rem; margin: 0 0 0.5rem; }
h2 { font-size: 1.35rem; margin: 2.25rem 0 0.5rem; padding-top: 1.25rem;
  border-top: 1px solid var(--borda); }
h3 { font-size: 1.1rem; margin: 1.75rem 0 0.25rem; }
p, ul { margin: 0.75rem 0; }
li { margin: 0.35rem 0; }
a { color: var(--teal); text-underline-offset: 0.15em; }
a:focus-visible { outline: 3px solid var(--teal); outline-offset: 2px; border-radius: 2px; }
strong { font-weight: 600; }
em:first-child:last-child { color: var(--tinta-secundaria); font-style: normal; }
code { font-size: 0.9em; }
.topo { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 2rem;
  color: var(--tinta); text-decoration: none; font-family: "Archivo", sans-serif;
  font-weight: 600; word-spacing: 0.08em; }
.topo img { width: 40px; height: 40px; border-radius: 10px; }
.apresentacao img { width: 96px; height: 96px; border-radius: 22px; }
.apresentacao p { color: var(--tinta-secundaria); font-size: 1.1rem; }
.links { list-style: none; padding: 0; margin: 2rem 0; }
.links li { margin: 0; }
.links a { display: block; padding: 0.9rem 1rem; margin: 0.5rem 0;
  background: var(--superficie); border: 1px solid var(--borda); border-radius: 12px;
  text-decoration: none; font-weight: 600; min-height: 48px; }
.links a:hover { background: var(--teal-claro); }
footer { margin-top: 3rem; color: var(--tinta-secundaria); font-size: 0.9rem; }
"""


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
<link rel="icon" href="{prefixo}icone.png">
<style>{estilo(prefixo)}</style>
</head>
<body>
<main>
{corpo}
</main>
</body>
</html>
"""


def converter(texto: str) -> str:
    corpo = markdown.markdown(
        texto,
        extensions=["tables", "toc"],
        extension_configs={"toc": {"slugify": slugify_unicode}},
        output_format="html",
    )
    # Links relativos para outros documentos do repositório apontam para o
    # GitHub: no site só existe a política.
    return re.sub(
        r'href="(?!https?:|#|mailto:)([^"]+\.md)(#[^"]*)?"',
        lambda m: f'href="{REPOSITORIO}/blob/main/docs/{m.group(1)}{m.group(2) or ""}"',
        corpo,
    )


def gerar(saida: Path) -> None:
    if saida.exists():
        shutil.rmtree(saida)
    (saida / "privacidade").mkdir(parents=True)
    (saida / "fontes").mkdir()

    for arquivo in FONTES:
        shutil.copy(RAIZ / "assets" / "fontes" / arquivo, saida / "fontes" / arquivo)
    shutil.copy(RAIZ / "docs" / "loja" / "icone-512.png", saida / "icone.png")

    texto = FONTE_POLITICA.read_text(encoding="utf-8")
    titulo = re.search(r"^# (.+)$", texto, re.MULTILINE).group(1).strip()
    topo = (
        '<a class="topo" href="../">'
        '<img src="../icone.png" alt="">SLAP Mobile</a>'
    )
    rodape = (
        f'<footer>Fonte: <a href="{REPOSITORIO}/blob/main/docs/privacidade.md">'
        "docs/privacidade.md</a> no repositório.</footer>"
    )
    (saida / "privacidade" / "index.html").write_text(
        pagina(
            titulo,
            "Quais dados o SLAP Mobile guarda, para onde vão e por quê.",
            topo + converter(texto) + rodape,
            prefixo="../",
        ),
        encoding="utf-8",
    )

    apresentacao = f"""<div class="apresentacao">
<img src="icone.png" alt="">
<h1>SLAP Mobile</h1>
<p>Inventário patrimonial offline e distribuído. Cada celular carrega os dados, funciona
sozinho e sincroniza direto com os outros pela rede local — sem servidor e sem internet.</p>
</div>
<ul class="links">
<li><a href="privacidade/">Política de privacidade</a></li>
<li><a href="{REPOSITORIO}/releases">Baixar o aplicativo</a></li>
<li><a href="{REPOSITORIO}">Código-fonte</a></li>
</ul>"""
    (saida / "index.html").write_text(
        pagina(
            "SLAP Mobile",
            "Inventário patrimonial offline e distribuído.",
            apresentacao,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    gerar(Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / "_site")
