# Etapa 2 — Arquitetura

Decisões técnicas do app, tomadas depois da análise em [`01-analise-slap.md`](01-analise-slap.md).

---

## 1. Stack: Flutter

Escolhido sobre React Native. O fator decisivo **não** foi UI nem produtividade — foi a
sincronização P2P.

| Requisito | Flutter | React Native |
|---|---|---|
| Descoberta na rede local (multicast UDP) | `RawDatagramSocket` no `dart:io`, nativo | `react-native-udp`, terceiros |
| Servidor HTTP embarcado no aparelho | `HttpServer` no `dart:io`, nativo | `react-native-tcp-socket`, terceiros |
| Banco local rápido | `package:sqlite3`, SQL direto e síncrono | `op-sqlite` / `expo-sqlite`, async |
| Leitura contínua de código de barras | `mobile_scanner` (MLKit), maduro | `vision-camera` + plugin, maduro |
| Lista de 10 mil itens | AOT compilado, sem ponte | ponte JS ou JSI |
| XLSX em código puro | `package:excel` | `sheetjs` |

A camada de rede é a parte mais difícil de depurar deste projeto, e é exatamente onde o React
Native dependeria de bibliotecas de terceiros pouco mantidas. Em Flutter ela é biblioteca padrão.

**Versões:** Flutter 3.38.5 / Dart 3.10.4.

### Gerenciamento de estado e navegação

`flutter_riverpod` e `go_router`. Riverpod porque o estado central do app — a configuração
pegajosa do levantamento — é lido por várias telas e precisa sobreviver à navegação, e porque
os providers são testáveis sem widget tree.

### Banco local: SQLite direto, sem ORM

O Drift foi tentado primeiro e **descartado**: `drift_dev` exige `analyzer ≥ 10.0.2`, que exige
`meta ^1.18.0`, e o Flutter 3.38.5 fixa `meta 1.17.0`. O codegen não roda nesta SDK.

Isso acabou sendo bom. Com SQL escrito à mão:

- controle direto dos índices, que é o que garante a busca instantânea exigida pela spec §49;
- `PRAGMA journal_mode=WAL` para leitura concorrente durante a sincronização;
- statements preparados reaproveitados no laço de importação;
- sem `build_runner` na cadeia de build.

Camada de acesso em `lib/data/`, com um repositório por agregado. Nenhum SQL fora dessa pasta.

---

## 2. Modelo de dados

O princípio que organiza tudo: **dado original do SUAP e dado encontrado no levantamento nunca
se misturam.** No SLAP eles convivem na mesma linha, distinguidos por convenção de nome. Aqui a
separação é estrutural.

### Tabelas

```
inventories       id, name, year, created_at, origin_device_id, sync_key, excluded_eds
assets            id, inventory_id,
                  -- original do SUAP, imutável após a importação:
                  ord, tombo, barcode, ed, description, responsible_original,
                  room_original, value, conservation_original, usage_original,
                  -- cache materializado do levantamento (derivado de asset_field):
                  verified, room_current, responsible_current,
                  conservation, usage_status, verified_at, verified_by_name
asset_field       asset_id, field, value, hlc, op_id, device_id      -- PK (asset_id, field)
ops               op_id, inventory_id, entity, entity_id, field, value,
                  hlc, device_id, seq, ctx_id, user_name, user_registration, created_at
causal_contexts   ctx_id, vector                                      -- dedup das version vectors
peers             device_id, inventory_id, user_name, last_seq_seen, last_sync_at
conflicts         id, inventory_id, asset_id, field, local_op_id, remote_op_id,
                  resolved_op_id, resolved_at
settings          key, value                                          -- identidade local
```

### Índices que importam

```sql
CREATE INDEX idx_assets_tombo    ON assets(inventory_id, tombo);
CREATE INDEX idx_assets_barcode  ON assets(inventory_id, barcode);
CREATE INDEX idx_assets_verified ON assets(inventory_id, verified);
CREATE INDEX idx_assets_room     ON assets(inventory_id, room_original);
CREATE INDEX idx_ops_sync        ON ops(inventory_id, device_id, seq);
```

Os dois primeiros são o caminho quente: toda leitura de patrimônio é um ponto de acesso por
`(inventory_id, tombo)` ou `(inventory_id, barcode)`. Com índice, é sublinear e imperceptível
mesmo com dezenas de milhares de itens.

### Normalização de tombo e código de barras

Os dois são **texto**, nunca inteiro — zeros à esquerda são significativos. Cada um é gravado
duas vezes: o valor cru (`tombo`) e uma forma normalizada usada só para busca.

A normalização corrige a sujeira encontrada na base real (§3 da análise):

1. remove espaços, pontos e hífens de formatação;
2. remove um sinal `-` inicial (a exportação do SUAP produz códigos negativos);
3. remove zeros à esquerda **apenas na chave de busca**, preservando o valor original no dado.

Assim `-19281`, `19281` e `019281` casam entre si na busca, mas o item continua exibindo o
valor exato que veio do SUAP.

### Busca cruzada

A análise mostrou que o SLAP nunca testa um número lido como tombo contra o campo de código de
barras, e a spec §25.2 aponta isso como causa frequente de falso "não localizado". Aqui a busca
tem duas etapas:

1. busca no campo do modo selecionado (tombo ou código de barras);
2. se não achar, busca no outro campo e, se achar, registra sucesso **sinalizando ao usuário**
   que o número estava no outro campo.

O item é encontrado, mas o usuário sabe que há inconsistência no cadastro.

---

## 3. Divergências: uma correção à especificação

A spec §29 pede divergência de **quatro** campos: sala, responsável, estado de conservação e
situação de uso.

**Os dois últimos não têm base de comparação.** A planilha exportada do SUAP não traz estado de
conservação nem situação de uso — por isso o SLAP grava esses campos mas nunca os compara com
nada. Sem valor anterior não existe divergência; existe apenas informação nova.

Tratamento adotado:

- O importador **aceita** colunas de estado e situação, caso a planilha as traga. Quando
  mapeadas, viram `conservation_original` / `usage_original` e a divergência funciona
  exatamente como a de sala e responsável.
- Quando ausentes, o valor levantado é registrado como informação nova e **não** torna o item
  divergente por si só.
- Independentemente disso, itens em estado `ruim` ou situação `inserv.` recebem uma marca de
  atenção, que aparece como coluna nos relatórios. São acionáveis mesmo sem valor anterior.

Isso mantém os três grupos da spec §31 limpos, sem inventar uma divergência que o dado não
sustenta.

### Classificação final

```
NÃO LOCALIZADO  → verified = false ao encerrar
DIVERGENTE      → verified = true E (sala ≠ sala_original
                                  OU responsável ≠ responsável_original
                                  OU (existe base) E estado ≠ estado_original
                                  OU (existe base) E situação ≠ situação_original)
OK              → verified = true E nenhuma diferença
```

Itens com ED excluído ficam fora dos três grupos e fora do denominador do progresso.

---

## 4. Identidade, sem login

Três identidades distintas, nenhuma exigindo senha:

| Identidade | Onde vive | Para quê |
|---|---|---|
| **Dispositivo** | UUIDv4 gerado na primeira execução, imutável | autoria das operações, desempate de conflito, endereço na sincronização |
| **Usuário** | nome + matrícula, editável | atribuir a verificação a uma pessoa nos relatórios e na auditoria |
| **Inventário** | UUIDv4 + `sync_key` | identificar o processo e autorizar quem sincroniza |

O `device_id` é o que dá consistência ao sistema distribuído; o nome do usuário é metadado
humano. Trocar o nome do usuário não afeta a convergência dos dados.

---

## 5. Sincronização

O núcleo do projeto. O desenho é um **CRDT baseado em operações, com last-writer-wins por campo
e detecção explícita de concorrência.**

Em uma frase: as réplicas convergem sozinhas e sem perder dado, e o sistema ainda consegue dizer
ao usuário *quando duas pessoas mexeram no mesmo campo sem saber uma da outra*.

### 5.1 Toda mudança é uma operação imutável

Nada é alterado em `assets` diretamente. Toda mudança acrescenta uma linha em `ops`:

```
op_id, inventory_id, entity='asset', entity_id=<asset>, field='room_current',
value='Biblioteca', hlc=..., device_id=..., seq=..., ctx_id=...,
user_name='Guilherme', user_registration='123456'
```

O log de operações **é** a fonte da verdade; `assets` é cache materializado. Isso resolve de uma
vez a sincronização incremental (spec §40), o registro de alterações (§41) e a auditoria (§47):
são a mesma estrutura.

### 5.2 Relógio híbrido (HLC)

Relógio de parede sozinho não serve — celulares têm relógios desalinhados. Contador lógico
sozinho também não — o usuário precisa ver quando a leitura aconteceu.

Cada operação carrega um **Hybrid Logical Clock**: `(milissegundos, contador, device_id)`,
serializado como string ordenável. Ele acompanha o tempo real quando o relógio avança e cai no
contador lógico quando não avança, garantindo ordem total sem perder o sentido humano de
"quando isso foi lido".

**Relógio fora de sincronia.** Um aparelho com a data errada é o caso comum que o HLC não pode
absorver: aceitar uma operação do futuro arrastaria o relógio de quem a recebe, e depois o de
todos, para o futuro. Acima de 5 minutos de diferença a sincronização é recusada, e a recusa é
explicada — qual aparelho, quanto adiantado ou atrasado, as duas horas lado a lado e a orientação
de ativar data e hora automáticas. Três pontos detectam o problema:

1. a apresentação (`/hello`) traz o horário do par, e o cliente confere antes de trocar qualquer
   operação;
2. a assinatura com a chave certa e horário fora da janela responde `409` com o horário de quem
   recusou, em vez do `401` de chave errada;
3. um lote com operação do futuro — que pode ser de um terceiro, escrita quando aquele aparelho
   estava com a data errada — é recusado inteiro, na mesma transação, e o autor é nomeado.

Nenhuma operação daquele par é aplicada até a diferença sumir.

### 5.3 Version vector e contexto causal

Cada dispositivo numera suas próprias operações com um `seq` monotônico. O estado de
conhecimento de uma réplica é uma **version vector**: `{deviceA: 412, deviceB: 87, deviceC: 0}`.

Cada operação guarda a version vector que o dispositivo tinha **no momento da escrita** — é o
que permite saber, depois, se quem escreveu já conhecia a escrita alheia.

Guardar a vector inteira em cada operação seria caro. Mas a componente local muda a cada
operação enquanto as componentes remotas só mudam quando ocorre uma sincronização. Então:

> guarda-se apenas a parte remota, deduplicada na tabela `causal_contexts`, e a componente
> local é implícita (`= op.seq`).

Na prática isso gera **uma linha de contexto por sincronização**, não por operação. Uma sessão
inteira de levantamento compartilha o mesmo `ctx_id`.

### 5.4 Detecção de concorrência

Com `VV(op) = ctx(op) ∪ {op.device: op.seq}`:

```
A aconteceu-antes-de B   ⟺   VV(B)[A.device] ≥ A.seq
A e B são concorrentes   ⟺   nenhuma das duas direções vale
```

Ao aplicar uma operação recebida sobre um campo que já tem valor:

- **causalmente ordenadas** → a mais recente vence, sem conflito. Não é conflito: alguém
  atualizou sabendo do valor anterior.
- **concorrentes e valores iguais** → nada a fazer.
- **concorrentes e valores diferentes** → grava uma linha em `conflicts` e **mesmo assim**
  aplica o LWW, para o banco nunca ficar num estado indefinido.

É esta distinção que evita a praga dos sistemas P2P ingênuos: alarme de conflito toda vez que
dois aparelhos sincronizam. Aqui só vira conflito o que é genuinamente concorrente — o caso da
spec §42, duas pessoas conferindo o mesmo patrimônio sem se falar.

### 5.5 Resolução

O LWW já deixou o banco consistente, então o conflito não bloqueia ninguém: ele aparece numa
lista de pendências. O usuário escolhe manter o local, aceitar o remoto ou digitar um terceiro
valor. Qualquer escolha grava uma **nova operação**, que por construção domina causalmente as
duas anteriores e encerra o conflito em todas as réplicas na próxima sincronização.

Empate de HLC (mesmo milissegundo e contador) é desempatado pelo `device_id`, que é único e
estável. Determinístico: todas as réplicas escolhem o mesmo vencedor sem se consultar.

### 5.6 Protocolo

Sem servidor central e sem papel fixo (spec §43). Cada aparelho é simultaneamente cliente e
servidor: um `HttpServer` do `dart:io` numa porta efêmera.

```
GET  /hello                      → identidade do aparelho e inventários que possui
POST /sync/pull  {inv, vector}   → operações que o solicitante não tem
POST /sync/push  {inv, ops[]}    → operações enviadas pelo solicitante
GET  /inventory/{id}/bundle      → réplica inicial completa (distribuição do §38)
```

Uma sincronização entre A e B é `pull` seguido de `push`, nos dois sentidos. Como cada réplica
**repassa operações de terceiros**, A↔B propaga o trabalho de C sem que A e C se encontrem —
o que faz a topologia em malha da spec §43 funcionar de verdade.

O `pull` envia a version vector do solicitante e recebe só o que falta: é a sincronização
incremental do §40, sem retransmitir o inventário inteiro.

### 5.7 Descoberta

Duas vias em paralelo, porque nenhuma é confiável sozinha:

1. **mDNS / DNS-SD** (`_slap-sync._tcp`) via `package:nsd`, que usa `NsdManager` no Android e
   `NetService` no iOS. Registra nos TXT: `device_id`, nome do usuário, porta.
2. **Beacon UDP multicast** em `239.7.7.7:47771`, a cada 3 segundos. Existe porque mDNS falha
   com frequência em rede de celular e em alguns pontos de acesso.

Nenhuma das duas atravessa isolamento de cliente ("AP isolation"). Quando a rede tem isolamento,
nada em software resolve — o app detecta a ausência de pares e orienta o usuário a usar um
hotspot próprio.

### 5.8 Entrar num inventário: QR code

A câmera já é permissão do projeto, então ela também resolve o pareamento.

O aparelho que criou o inventário mostra um QR com `{inventory_id, nome, ano, sync_key}`.
Quem escaneia passa a conhecer a chave, encontra o par na rede e puxa o bundle inicial.

Isso responde três coisas de uma vez: quem participa do inventário, como a réplica inicial chega
ao aparelho (§38) e como autorizar a sincronização.

### 5.9 Segurança e seu limite

Toda requisição é assinada com HMAC-SHA256 da `sync_key` do inventário, sobre método, caminho,
hash do corpo e timestamp. Quem não tem a chave não lê nem escreve, e uma requisição capturada
não pode ser modificada nem repetida fora da janela de tempo.

**Limitação assumida e documentada:** o corpo trafega em claro. Na rede local, quem já estiver
autenticado nela e capturando pacotes consegue ler dados patrimoniais — descrição, sala,
responsável. Não há credencial nem dado pessoal sensível no tráfego, e o alcance é o segmento
local. Cifrar o corpo com AES-GCM derivado da `sync_key` está no roteiro; não entrou na v1 para
não adicionar dependência de criptografia antes do protocolo estar estável.

---

## 6. Velocidade

A spec §12 e §49 colocam velocidade como requisito de primeira ordem. As decisões que a
sustentam:

- **Configuração pegajosa**, herdada do SLAP: sala, estado, situação e responsável são
  definidos uma vez e aplicados às leituras seguintes. Uma leitura = zero toques na tela.
- **Busca indexada local**, sem rede no caminho da leitura.
- **Áudio pré-carregado**: os três sons ficam decodificados em memória; o feedback sai junto
  com a leitura, não depois dela.
- **Gravação assíncrona**: o som e o retorno visual não esperam o commit no SQLite.
- **Importação em isolate**, com transação única e statement preparado, para não travar a UI.
- **Leitura em lote pela câmera** (§24): a câmera não fecha entre itens; os códigos entram numa
  fila e são processados em segundo plano enquanto a captura continua. O "OK" só confirma o que
  já foi processado.

---

## 7. Permissões

Apenas as duas que o projeto pediu.

**Android**

| Permissão | Por quê |
|---|---|
| `CAMERA` | leitura de código de barras e do QR de pareamento |
| `INTERNET` | exigida pelo Android para abrir qualquer socket, inclusive local |
| `ACCESS_NETWORK_STATE` | saber se há Wi-Fi antes de tentar descobrir pares |
| `CHANGE_WIFI_MULTICAST_STATE` | `MulticastLock`, sem o qual o Android descarta pacotes multicast |

Sem localização, sem armazenamento, sem contas. Importar e exportar arquivo usa o seletor do
sistema (SAF), que não exige permissão.

**iOS**

`NSCameraUsageDescription`, `NSLocalNetworkUsageDescription` e `NSBonjourServices` declarando
`_slap-sync._tcp`.

---

## 8. Importação

- **XLSX** e **CSV**. O `.xls` antigo (único formato que o SLAP lia) não é suportado: a
  especificação pede XLSX e CSV, e manter um leitor BIFF custaria mais do que orientar a
  conversão.
- **Mapeamento por nome de coluna**, com normalização (minúsculas, sem acento, sem pontuação) e
  dicionário de sinônimos por campo. Cabeçalho procurado nas primeiras linhas, porque exportação
  do SUAP costuma ter linhas de título antes.
- **Confirmação sempre.** Mesmo quando o mapeamento automático acerta tudo, a tela mostra o que
  foi reconhecido, com amostra das primeiras linhas, e permite corrigir qualquer coluna.
- **Filtro de ED orientado a dado**: o importador lê os EDs presentes no arquivo, com a contagem
  de itens de cada um, e o usuário marca quais ignorar. Nenhum código de ED fica gravado no app —
  isso funciona com qualquer versão da planilha, o que uma lista fixa não faria.
- **Reimportação reconcilia**, não apaga. Itens novos entram, itens ausentes são apontados, e
  itens já verificados nunca perdem a verificação sem confirmação explícita. É a correção do
  problema mais grave encontrado no SLAP.

---

## 9. Relatórios

XLSX e CSV, gerados de qualquer réplica (spec §45) — como toda réplica tem o log completo de
operações, qualquer aparelho sincronizado produz o mesmo relatório.

| Relatório | Conteúdo |
|---|---|
| **Itens OK** | encontrados, sem diferença — não precisam de alteração no SUAP |
| **Divergências** | uma linha por campo alterado: tombo, campo, valor SUAP, valor encontrado, quem, quando |
| **Não localizados** | tombo, descrição, sala original, responsável original |
| **Completo** | todos os itens com situação e classificação |

O relatório de divergências sai no formato longo (uma linha por campo), que é o que a spec §34
pede e o que serve para conferência item a item no SUAP.

---

## 10. Estrutura do código

```
lib/
  main.dart
  app/            tema, rotas, inicialização
  core/           HLC, version vector, normalização, ids, resultado de leitura
  data/
    db.dart       abertura, PRAGMAs, migrations
    schema.dart   DDL
    repos/        um repositório por agregado — todo o SQL vive aqui
  domain/         entidades e regras puras (divergência, classificação)
  features/
    identity/     identidade local do usuário e do dispositivo
    inventory/    lista, criação, dashboard
    import/       leitura de planilha, mapeamento de colunas, filtro de ED
    survey/       levantamento: configuração pegajosa, leitura, câmera, sons
    divergence/   listas e classificação
    sync/         descoberta, servidor, cliente, conflitos
    reports/      geração de XLSX e CSV
```

Regra de dependência: `features` → `domain` → `core`. `data` é acessado pelas features apenas
através dos repositórios. Nada em `domain` importa Flutter, o que mantém as regras de negócio
testáveis sem widget tree.
