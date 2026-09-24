# Listagem na Play Store

Tudo o que o Play Console pede para a ficha do aplicativo, pronto para colar. Os textos seguem os
limites da loja (conferidos: nome ≤ 30, descrição curta ≤ 80, descrição completa ≤ 4000
caracteres). O que só dá para fazer no Play Console está em [Falta fazer](#falta-fazer).

## Textos

**Nome do app** (29 caracteres)

```
SLAP — Inventário Patrimonial
```

**Descrição curta** (77 caracteres)

```
Inventário patrimonial sem internet: leia os códigos e sincronize no celular.
```

**Descrição completa**

```
O SLAP Mobile faz o inventário patrimonial pelo celular, sem depender de servidor nem de internet.

Cada aparelho carrega uma cópia completa do inventário e trabalha sozinho. Quando os aparelhos estão na mesma rede Wi-Fi, trocam o que cada um levantou, direto entre eles.

COMO FUNCIONA
• Importe a planilha de patrimônios exportada do SUAP (XLSX ou CSV). As colunas são reconhecidas pelo nome.
• Os colegas entram no inventário lendo um QR code.
• Cada pessoa levanta uma sala: leia o código de barras pela câmera ou com um leitor externo, ou digite o tombo.
• Cada resultado tem som, vibração, cor e texto próprios: registrado, já verificado ou não localizado.
• Sincronize quando quiser. Se duas pessoas alterarem o mesmo item sem sincronizar, o aplicativo mostra o conflito para decidir — nada se perde em silêncio.

NO FIM
• Os patrimônios separados em três grupos: os que estão certos, os que precisam de atualização no SUAP (sala ou responsável) e os não localizados. O estado de conservação e a situação de uso levantados saem nos relatórios.
• Relatórios em XLSX ou CSV para cada grupo.

PRIVACIDADE
• Sem conta, sem servidor, sem anúncios.
• Os dados ficam no aparelho e só trafegam, cifrados, entre os celulares do mesmo inventário.
• Cópia de segurança do inventário num arquivo que você guarda onde quiser.

ACESSIBILIDADE
• Funciona com TalkBack, fonte ampliada e tema escuro.

Software livre, licença Apache-2.0: github.com/guilhermefeitosa66/slap-mobile
```

## Imagens

| Item | Arquivo | Requisito da loja |
|---|---|---|
| Ícone | [`icone-512.png`](icone-512.png) | 512 × 512, PNG |
| Imagem de destaque | [`destaque.png`](destaque.png) | 1024 × 500, sem transparência |
| Capturas de celular | [`capturas/celular-*.png`](capturas/) | 1080 × 1920 (9:16), de 2 a 8 |
| Capturas de tablet | [`capturas/tablet-*.png`](capturas/) | 1800 × 3200 (9:16); servem para 7 e 10 polegadas |

Ordem sugerida para o celular — o levantamento primeiro, porque é o que o aplicativo faz:

1. `celular-3-levantamento.png`
2. `celular-2-painel.png`
3. `celular-4-divergentes.png`
4. `celular-5-relatorios.png`
5. `celular-1-inventarios.png`
6. `celular-7-levantamento-escuro.png`
7. `celular-8-painel-escuro.png`
8. `celular-6-identidade.png`

Tablet: a mesma ordem, de `tablet-3` a `tablet-6`, depois `tablet-1`.

Tudo é gerado a partir do código, com dados fictícios:

- capturas: `flutter test --run-skipped --tags capturas --update-goldens`
  (`test/capturas/capturas_test.dart`);
- ícone: `python3 tool/gerar_icones.py`;
- imagem de destaque: `.venv-marca/bin/python tool/gerar_marca.py`, junto com
  a logomarca (ver [`../marca/README.md`](../marca/README.md)).

## Classificação e categoria

- **Categoria:** Empresas (Business). Tags: inventário, patrimônio, código de barras.
- **Público-alvo:** 18 anos ou mais — é ferramenta de trabalho de servidores públicos. Assim o app
  fica fora das regras de famílias.
- **Anúncios:** o app não contém anúncios.
- **Classificação indicativa** (questionário IARC):
  - Categoria do app: *Utilitário, produtividade, comunicação ou outro*.
  - Violência, sexo, linguagem imprópria, drogas, jogos de azar: **não** para todas.
  - Os usuários interagem ou trocam conteúdo? **Sim** — os aparelhos do mesmo inventário trocam
    registros (leituras, com o nome de quem conferiu). Não há chat nem conteúdo livre.
  - Compartilha a localização do usuário? **Não**. Compras digitais? **Não**.
  - Resultado esperado: **Livre**, com o aviso de interação entre usuários.

## Privacidade e permissões

- **Política de privacidade:** `https://guilhermefeitosa66.github.io/slap-mobile/privacidade/`
- **Segurança dos dados:** respostas e justificativa em [seguranca-de-dados.md](seguranca-de-dados.md).

  > A issue #18 previa declarar que o aplicativo não coleta dados. **No Android isso não é
  > verdade hoje:** a biblioteca de leitura de código (ML Kit, do Google) envia diagnósticos dela
  > ao Google, e o formulário precisa dizer isso. O detalhe está em
  > [seguranca-de-dados.md](seguranca-de-dados.md).

- **Uso da câmera**, para o formulário e as notas de revisão:

  > A câmera é usada só para ler os códigos de barras das etiquetas de patrimônio e o QR code que
  > dá entrada num inventário. O reconhecimento é feito no aparelho; nenhuma foto ou vídeo é
  > gravado ou enviado. A permissão é pedida quando a pessoa abre a câmera pela primeira vez, e o
  > aplicativo funciona sem ela com um leitor de código externo ou digitando o tombo.

## Acesso ao app (instruções para a revisão)

Não há login. Para ver o aplicativo com dados:

> 1. Na primeira abertura, informe qualquer nome e toque em Começar.
> 2. Baixe a planilha de demonstração no aparelho:
>    https://github.com/guilhermefeitosa66/slap-mobile/raw/main/docs/loja/planilha-demonstracao.xlsx
> 3. Toque em Novo, dê um nome ao inventário e importe a planilha baixada (60 patrimônios
>    fictícios, em cinco salas).
> 4. No painel, toque em Levantar, escolha uma sala, mude para "Tombo" e digite, por exemplo,
>    023101, 023105 ou 999999 (este último aparece como não localizado).
> 5. Volte ao painel para ver os grupos e os relatórios.
>
> A sincronização precisa de um segundo aparelho na mesma rede Wi-Fi: no primeiro, em
> Sincronizar, o ícone de QR code mostra o código do inventário; no segundo, o ícone de QR code da
> lista de inventários ("Entrar em um inventário") lê esse código.

A planilha é gerada por `dart run tool/gerar_planilha_demonstracao.dart`, e
`test/features/planilha_demonstracao_test.dart` garante que ela continua sendo importada inteira.

## Falta fazer

Passos no Play Console, que dependem da conta de desenvolvedor:

- [ ] Criar o app e preencher a ficha com os textos e imagens acima.
- [ ] E-mail de contato do desenvolvedor (obrigatório na ficha; não entra no repositório).
- [ ] Questionário de classificação indicativa.
- [ ] Público-alvo, anúncios e acesso ao app.
- [ ] Formulário de segurança dos dados ([seguranca-de-dados.md](seguranca-de-dados.md)).
- [ ] URL da política, depois de ativar o GitHub Pages (Settings → Pages → Source: GitHub Actions).
- [ ] Assinatura de apps do Google Play — a decisão está em [../assinatura.md](../assinatura.md).
