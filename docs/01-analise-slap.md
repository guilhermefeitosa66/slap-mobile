# Etapa 1 — Análise do SLAP

Levantamento das regras de negócio do sistema atual (Rails 4.2, `~/projetos/ifpi/slap`),
feito para extrair o que precisa ser preservado e o que precisa ser corrigido.

Commit analisado: `fb4f6b6`. O sistema tem 4 migrations, 4 models e 5 controllers — é pequeno,
então a análise abaixo cobre 100% do código, não uma amostra.

---

## 1. Modelo de dados atual

Não existe `schema.rb` versionado; o esquema real vem das migrations.

### `users` (Devise)
`email`, `encrypted_password`, `name`, `admin:boolean` + campos de recoverable/rememberable/trackable.

### `inventories`
| Campo | Tipo | Observação |
|---|---|---|
| `year` | string | ano do inventário |
| `campus` | string | selecionado de uma lista fixa de 21 campi |
| `file` | string | planilha anexada (CarrierWave) |

Validações: `year`, `campus` e `file` são todos obrigatórios.

### `inventory_users`
Tabela de junção `inventory` ↔ `user`. Define quem é a comissão de inventário.

### `items`
| Campo | Tipo | Origem |
|---|---|---|
| `ord` | string | SUAP |
| `cbarra` | string | SUAP — código de barras |
| `tombo` | string | SUAP |
| `ed` | string | SUAP — elemento de despesa |
| `descricao` | text | SUAP |
| `responsavel` | string | SUAP — responsável original |
| `sala` | string | SUAP — sala original |
| `valor` | string | SUAP |
| `campus` | string | **nunca preenchido pelo importador** (campo morto) |
| `verified` | boolean | levantamento |
| `estado_conservacao` | string | levantamento |
| `situacao_uso` | string | levantamento |
| `sala_atual` | string | levantamento |
| `responsavel_atual` | string | levantamento |
| `user_id` | FK | quem verificou (**apenas o último**) |
| `inventory_id` | FK | |

**Observação central:** dados originais do SUAP e dados encontrados no levantamento convivem
na mesma linha, distinguidos apenas por convenção de nome (`sala` vs `sala_atual`). Não há
histórico: cada nova gravação sobrescreve a anterior.

Todos os campos numéricos são `string`. Isso é acidental, mas acabou sendo protetivo —
guardar tombo como inteiro perderia zeros à esquerda.

---

## 2. Valores de domínio

Extraídos de `app/views/items/check.html.erb` (são literais no `select`, não há tabela nem enum):

**Estado de conservação:** `bom` · `regular` · `ruim`

**Situação de uso:** `ativo` · `ocioso` · `inserv.`

> A especificação inicial do app supunha `Bom/Ruim/Inservível` e `Em uso/Não utilizado`.
> Os valores reais do SLAP são os seis acima — "inservível" é situação de uso, não estado de
> conservação. O app novo adota os valores reais.

Não há valor vazio nem "não informado": o `select` sempre envia algo, e o default é o primeiro
(`bom` / `ativo`). Na prática, **todo item verificado no SLAP recebe estado e situação**, mesmo
que o usuário não tenha pensado a respeito.

### Achado: modelo antigo abandonado

`app/views/items/export.xlsx.axlsx` referencia `i.bom`, `i.reg`, `i.ruim`, `i.ativo`, `i.ocioso`,
`i.inserv` — seis colunas booleanas que **não existem no schema**. É uma view morta de um modelo
anterior, que foi colapsado nos dois campos string atuais. A view quebra se acionada, mas não há
rota que a alcance.

---

## 3. Importação da planilha

`InventoriesController#migrate_spreadsheet`:

```ruby
book = Spreadsheet.open(...)          # gem 'spreadsheet' → lê .xls (BIFF), NÃO lê .xlsx
inventory.items.destroy_all           # apaga tudo antes de importar
sheet1.each_with_index do |row, i|
  next if i == 0                      # pula cabeçalho
  ord:    row[0].to_i, cbarra: row[1].to_i, tombo: row[2].to_i, ed: row[3].to_i,
  descricao: row[4], responsavel: row[5], sala: row[6], valor: row[7]
  inventory.items.create!(attributes) # insert individual, sem transação
end
```

**Formato exigido** (confirmado por `app/assets/images/exemplo-planilha.png`), posicional e rígido:

| A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|
| ORDEM | COD. BARRAS | TOMBO | ED | DESCRIÇÃO | RESPONSAVEL | SALA | VALOR |

### Problemas encontrados

1. **Reimportar destrói o levantamento.** `destroy_all` apaga todos os itens e, com eles, todo o
   trabalho já verificado. Não há aviso.
2. **Posicional.** Inserir ou reordenar uma coluna no SUAP quebra a importação silenciosamente —
   os dados entram nos campos errados, sem erro.
3. **`.to_i` destrói zeros à esquerda.** Um tombo `000123` vira `123`.
4. **Só lê `.xls`.** A gem `spreadsheet` não abre `.xlsx`. Exportações modernas do SUAP precisam
   ser convertidas à mão antes.
5. **Sem transação.** Falha no meio deixa importação parcial, com os itens antigos já apagados.
6. **Sem filtro de ED.** O campo é importado, mas nunca usado para nada. Material bibliográfico
   entra no inventário como qualquer outro item e vira pendência que ninguém vai conferir.

### Achado: códigos de barras negativos

A planilha de exemplo mostra códigos de barras **negativos** (`-19281`, `-17033`, `-17025`) com
tombos positivos e diferentes (`23254`, `25502`, `25510`). Confirma dois pontos da especificação:

- tombo e código de barras são mesmo campos independentes (§19–20 da spec);
- a exportação do SUAP tem sujeira de formatação que precisa ser normalizada na importação,
  e não pode ser normalizada com `.to_i`, que preserva o sinal negativo.

Como a busca faz `params[:cbarra].to_i.to_s`, ler `19281` no leitor **não encontra** o item
gravado como `-19281`. É um bug real de produção.

---

## 4. Fluxo de levantamento

O fluxo rápido do SLAP — a parte que a especificação pede explicitamente para preservar.

```
choose_inventory → room (escolhe sala) → check (lê, lê, lê, ...)
```

### Configuração em sessão

`ItemsController#check` guarda a configuração corrente na **sessão**, não no banco:

```ruby
session[:sala]        = params[:item][:sala]
session[:item_status] = { estado_conservacao:, situacao_uso:, responsavel_atual: }
```

O formulário é reconstruído a cada leitura com `Item.new(session[:item_status])`, o que mantém os
selects preenchidos. **É daí que vem a velocidade:** o usuário configura uma vez e as leituras
seguintes herdam tudo. Esse é o mecanismo central a preservar.

### Busca do patrimônio

```ruby
if cbarra presente
  @item = Item.where(cbarra: cbarra.to_i.to_s, inventory_id: id).first
elsif tombo presente
  @item = Item.where(tombo: tombo.to_i.to_s, inventory_id: id).first
end
```

- código de barras tem **precedência** sobre tombo;
- a busca é sempre **escopada ao inventário**;
- `.first` — se houver duplicados, pega um silenciosamente;
- **não há busca cruzada**: um número lido no campo "tombo" nunca é testado contra `cbarra`.
  A spec (§25.2) cita isso como causa frequente de "não localizado".

### Os três estados da leitura

| Situação | Condição no código | Som |
|---|---|---|
| **Sucesso** | item existe e `!verified` | `success-2.wav` |
| **Já verificado** | item existe e `verified` | `alert.wav` |
| **Não localizado** | `@item.nil?` | `error.wav` |

Os três `.wav` estão em `public/` e são tocados via `new Audio(...).play()` inline na view.
Confirma §25–27 da especificação: a diferenciação sonora já existe e é parte da operação.

No caso "já verificado" o SLAP **não sobrescreve**. Mostra quem verificou e oferece um botão
"Modificar" que reenvia com `change: true`, forçando a regravação. A spec §26 pede exatamente
esse comportamento.

### Gravação

```ruby
@item.user_id   = current_user.id
@item.sala_atual = session[:sala]
@item.verified   = true
@item.update(item_params)   # estado_conservacao, situacao_uso, responsavel_atual
```

E no model `Item`:

```ruby
before_save { item.responsavel_atual = item.responsavel if responsavel_atual.blank? }
```

**Regra do responsável:** se o usuário não escolher um responsável novo, o original é copiado
para `responsavel_atual`. Consequência: `responsavel == responsavel_atual` significa
"sem mudança de responsável". A spec §18 descreve essa regra.

### Leitura por câmera

Via **ZXing externo** (`zxing://scan/`), com o APK servido em `public/zxing.apk`. Abre o app de
scanner, volta à página pelo hash da URL, preenche o campo e dá submit. Uma leitura por vez,
com troca de aplicativo a cada item. É o ponto mais lento do fluxo atual e o que a spec §23–24
quer substituir por câmera contínua embutida.

### Desfazer

`ItemsController#undo` zera `verified` e anula os quatro campos de levantamento. Não há registro
de que o undo aconteceu.

---

## 5. Divergências e progresso

### Cálculo de progresso (`Inventory#progress`)

```ruby
(items.where(verified: true).count * 100) / items.count   # divisão inteira; rescue → 0
```

Só existe um percentual: verificados sobre total. Não há recorte por sala nem por usuário.

### Critério de divergência (`export_divergent.html.erb`)

```ruby
if i.sala != i.sala_atual || i.responsavel != i.responsavel_atual
```

**Apenas sala e responsável** contam como divergência. Estado de conservação e situação de uso
são gravados mas **nunca comparados** com nada — o SUAP original não traz esses campos na
planilha, então não há valor anterior com que comparar.

> Consequência para o app novo: a spec §29 pede divergência de conservação e situação de uso.
> Isso **não existe no SLAP** e não existe no app novo: os dois campos são levantados em campo, e
> a importação não os lê. A exportação atual do SUAP até traz uma coluna `ESTADO DE CONSERVAÇÃO`,
> mas com outro vocabulário, e ela é ignorada. Ver a decisão em `02-arquitetura.md`.


O relatório só considera itens `verified: true`.

---

## 6. Relatórios

### `inventories#export` — XLSX completo

Colunas: `ORDEM, COD. BARRAS, TOMBO, ED, DESCRIÇÃO, RESPONSAVEL ATUAL, SALA ATUAL, VALOR,
ESTADO DE CONSERVAÇÃO, SITUAÇÃO DE USO`

Com coalescência dos valores:

```ruby
sala        = i.sala_atual.nil?           ? i.sala        : i.sala_atual
responsavel = i.responsavel_atual.blank?  ? i.responsavel : i.responsavel_atual
```

Exporta **todos** os itens, verificados ou não — sem distinguir "não localizado" de "conferido e
igual". Quem recebe a planilha não consegue separar os três grupos.

### `inventories#export_divergent` — HTML para impressão

"Relatório de transferência patrimonial". Só itens verificados com mudança de sala ou responsável,
no formato `DO LOCAL: x / PARA: y`. É HTML impresso via `window.print()`, não é arquivo.

### O que não existe

- **Relatório de não localizados.** Não há. É a lacuna mais grave: `verified: false` ao final do
  inventário significa "não encontrado", mas nenhuma tela ou export mostra essa lista.
- **Relatório de itens OK.** Não há.
- **Exportação CSV.** Não há.

---

## 7. Salas e responsáveis

Ambos são derivados dos dados importados, com `SELECT DISTINCT`:

```ruby
Item.select(:sala).where(inventory_id: id).uniq.order(sala: :asc)
Item.select(:responsavel).uniq.order(responsavel: :asc)   # sem escopo de inventário (bug)
```

**Limitação relevante:** só é possível escolher uma sala que **já exista na planilha do SUAP**.
Não dá para inventariar um item numa sala nova, nem corrigir um nome de sala. O app novo precisa
aceitar texto livre com sugestões.

A lista de responsáveis não é escopada por inventário — mistura responsáveis de todos os
inventários do banco.

---

## 8. Usuários e permissões

- `admin: true` → vê o painel (`/inventories`, `/manager/users`).
- `admin: false` → é redirecionado para `choose_inventory` e só vê os inventários em que foi
  incluído pela comissão.

A única coisa que a identidade do usuário produz no dado final é `items.user_id`: **quem gravou
por último**. Não há histórico de quem mexeu antes.

---

## 9. Respostas às 20 perguntas da especificação (§52)

| # | Pergunta | Resposta |
|---|---|---|
| 1 | Campos do patrimônio | `ord, cbarra, tombo, ed, descricao, responsavel, sala, valor` (SUAP) + `verified, estado_conservacao, situacao_uso, sala_atual, responsavel_atual, user_id` (levantamento) |
| 2 | Como representa o tombo | `string`, importado com `.to_i` (perde zeros à esquerda) |
| 3 | Como representa o cód. barras | `string`, campo independente do tombo; há valores negativos na base real |
| 4 | Estados de conservação | `bom`, `regular`, `ruim` |
| 5 | Situações de uso | `ativo`, `ocioso`, `inserv.` |
| 6 | Responsável | string livre vinda do SUAP; `responsavel` (original) e `responsavel_atual` (encontrado) |
| 7 | Sala | string livre vinda do SUAP; `sala` e `sala_atual`; escolha limitada ao que existe na planilha |
| 8 | Divergências | `sala != sala_atual \|\| responsavel != responsavel_atual`, só para itens verificados |
| 9 | Progresso | `verificados * 100 / total`, divisão inteira |
| 10 | Usuários ↔ inventário | tabela de junção `inventory_users`, definida pelo admin |
| 11 | Importação XLSX | não existe — a gem lê apenas `.xls` |
| 12 | Formato da planilha | 8 colunas posicionais, 1 linha de cabeçalho ignorada |
| 13 | Elementos de despesa | importados como `ed`, **nunca usados**; não há lista nem filtro |
| 14 | Geração dos relatórios | `axlsx` para XLSX; HTML + `window.print()` para divergências |
| 15 | Dados exportados | todos os itens, com sala/responsável coalescidos |
| 16 | Validações | só `year`, `campus`, `file` no inventário e `name` no usuário; **nenhuma** em item |
| 17 | Regras para patrimônios antigos | nenhuma explícita — o descasamento tombo≠cbarra é consequência do dado, não de regra |
| 18 | Itens duplicados | não trata; `.first` escolhe um silenciosamente |
| 19 | Item já inventariado | flag `verified`; ao reler, mostra quem verificou e exige confirmação para sobrescrever |
| 20 | Regras a preservar | configuração persistente aplicada às leituras seguintes; 3 estados sonoros; não sobrescrever silenciosamente; responsável original preservado quando não alterado |

---

## 10. O que preservar e o que corrigir

### Preservar

1. **Configuração pegajosa** (sala + estado + situação + responsável) aplicada automaticamente às
   leituras seguintes. É a origem da velocidade do sistema.
2. **Três estados sonoros distintos** — sucesso, já verificado, não localizado.
3. **Não sobrescrever em silêncio** item já verificado; exigir confirmação explícita.
4. **Responsável original preservado** quando nenhum novo é informado.
5. **Busca escopada ao inventário**, por tombo ou por código de barras.
6. **Dado original do SUAP nunca é perdido** (`sala` vs `sala_atual`).

### Corrigir

| Problema no SLAP | Tratamento no app novo |
|---|---|
| Reimportar apaga o levantamento | importação reconcilia; nunca descarta verificação sem confirmação |
| Colunas posicionais | mapeamento por nome, com fallback manual |
| `.to_i` destrói zeros à esquerda | tombo e código de barras tratados como texto, normalizados sem perda |
| Código de barras negativo não casa com a leitura | normalização que remove sujeira de formatação e busca cruzada tombo↔código |
| Só lê `.xls` | XLSX + CSV |
| ED importado mas nunca usado | filtro de ED na importação |
| Sem relatório de não localizados | relatório próprio dos três grupos |
| Sem CSV | XLSX + CSV |
| Só guarda o último que gravou | log de alterações completo e auditável |
| Sala limitada ao que veio do SUAP | texto livre com sugestões |
| Duplicados escolhidos com `.first` | detectados e apresentados ao usuário |
| Estado/situação nunca comparados | ver decisão em `02-arquitetura.md` |
| Só uma leitura por vez, trocando de app | câmera contínua embutida, leitura em lote |
