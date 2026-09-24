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
                  room_original, value,
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

**Os dois últimos não têm base de comparação.** Estado de conservação e situação de uso são
levantados em campo; a importação não os lê. A exportação do SUAP até traz uma coluna
`ESTADO DE CONSERVAÇÃO` e uma `STATUS`, mas com outro vocabulário (Bom / Antieconômico /
Recuperável / Irrecuperável; Ativo / Baixado / Pendente) — tratá-las como valor de origem
inventava divergência onde só há vocabulário diferente. O SLAP grava esses campos e nunca os
compara com nada, e o app novo faz o mesmo: sem valor anterior não existe divergência; existe
apenas informação nova.

Tratamento adotado:

- O importador **não oferece** estado nem situação entre os campos da planilha, e o patrimônio
  não tem `conservation_original` / `usage_original` — as colunas existiram até a versão 3 do
  esquema e a migração para a 4 as remove.
- O valor levantado é registrado como informação nova e **não** torna o item divergente por si
  só.
- Itens em estado `ruim` ou situação `inserv.` recebem uma marca de atenção, que aparece como
  coluna nos relatórios. São acionáveis mesmo sem valor anterior.

Isso mantém os três grupos da spec §31 limpos, sem inventar uma divergência que o dado não
sustenta.

### Classificação final

```
NÃO LOCALIZADO  → verified = false ao encerrar
DIVERGENTE      → verified = true E (sala ≠ sala_original
                                  OU responsável ≠ responsável_original)

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
GET  /hello                          → identidade, versão e horário do aparelho (em claro)
POST /sync/pull?inventario={id}      → {vetor, cabeças} → operações que o solicitante não tem
POST /sync/push?inventario={id}      → {ops[], contextos, vetor, cabeças} → aplica
GET  /inventario/pacote?inventario={id} → réplica inicial: inventário e dados do SUAP
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

No Android o beacon depende do `MulticastLock`: sem ele o Wi-Fi descarta os pacotes multicast
recebidos, e o beacon envia mas nunca recebe — um defeito silencioso, porque o mDNS continua
achando alguns aparelhos. O `MainActivity` expõe a trava pelo canal `slap/rede`; a descoberta a
adquire ao iniciar e a libera ao parar, e também logo no início se nenhuma via subir. Trava negada
fica no log (`slap.descoberta`) e vira aviso na tela, em vez de sumir.

Para conferir o beacon sozinho, com o mDNS desligado, gere o APK com
`--dart-define=SLAP_DESCOBERTA=beacon`: dois aparelhos na mesma rede têm de se encontrar só por ele
(o ícone do aparelho na lista mostra por qual via ele foi achado).

Nenhuma das duas atravessa isolamento de cliente ("AP isolation"). Quando a rede tem isolamento,
nada em software resolve — o app detecta a ausência de pares e orienta o usuário a usar um
hotspot próprio.

### 5.8 Entrar num inventário: QR code

A câmera já é permissão do projeto, então ela também resolve o pareamento.

O aparelho que criou o inventário mostra um QR com `{inventory_id, nome, ano, sync_key}`.
Quem escaneia passa a conhecer a chave, encontra o par na rede e puxa o bundle inicial.

Isso responde três coisas de uma vez: quem participa do inventário, como a réplica inicial chega
ao aparelho (§38) e como autorizar a sincronização.

Quem lê o QR também passa pelo pedido de entrada, e é do aceite que vem a chave que ele usa: um só
fluxo de entrada, dois jeitos de chegar a ele. Ver §5.11.

### 5.9 Segurança

Três camadas, todas derivadas da `sync_key` que o QR code entrega:

- **Autenticação.** Toda requisição é assinada com HMAC-SHA256 sobre método, caminho, hash do
  corpo e timestamp. Quem não tem a chave não lê nem escreve, e uma requisição capturada não pode
  ser modificada nem repetida fora da janela de 5 minutos. Chave errada e inventário inexistente
  recebem a mesma resposta, para não confirmar a existência do inventário a quem não tem a chave.
- **Sigilo (protocolo 2).** O corpo de cada requisição e de cada resposta autenticada vai cifrado
  com AES-256-GCM — antes, quem estivesse na mesma rede capturando pacotes lia descrição, sala e
  responsável dos patrimônios. O conteúdo é comprimido com gzip antes de cifrar, e o GCM autentica
  também método, caminho e sentido: um corpo não serve em outra rota, e uma resposta não passa por
  pedido. Nonce de 96 bits de `Random.secure()`, novo a cada mensagem; com a mesma chave, a chance
  de repetir é desprezível muito além das 2^32 mensagens — um inventário troca alguns milhares.
  Na rede vai `base64url(nonce ‖ cifrado ‖ etiqueta)`, e a assinatura cobre esse texto.
- **Separação de chaves.** A `sync_key` não é usada direto: HKDF-SHA256 deriva dela uma chave para
  a cifra (`slap/sync/cifra`) e outra para a assinatura (`slap/sync/assinatura`).
- **Isolamento entre inventários.** A chave vale por inventário, e o alcance dela termina no
  inventário que a query identificou — aquele cuja chave conferiu a assinatura. O corpo que
  declarar outro é recusado antes de qualquer leitura, nos dois lados da conversa: sem isso,
  bastava pedir um inventário na query e falar de outro no corpo para ler o log alheio ou
  renomeá-lo, e o identificador do alvo aparece em claro na query de qualquer outra sincronização.
  A recusa não para no envelope. Antes de aplicar, o lote inteiro cai se alguma operação é de fora
  do inventário, e são três jeitos de ser: o `inventory_id` da operação, a operação sobre a
  entidade `inventario` apontando para outro id e a operação sobre patrimônio que esta réplica
  sabe ser de outro. Patrimônio desconhecido continua entrando — uma importação feita noutro
  aparelho depois da entrada cria itens que este nunca recebeu.
- **Contextos causais são endereçados pelo conteúdo.** A tabela `causal_contexts` é global, sem
  coluna de inventário. Aceitar o `ctx_id` que o remetente escolhesse permitiria plantar, sob o
  identificador que uma operação alheia vai citar, um vetor que mente conhecer a escrita do outro
  — e duas leituras concorrentes viram "atualização", com o conflito sumindo sem ninguém ver. O
  identificador é recalculado do vetor ao receber, e só entram os contextos que alguma operação do
  próprio lote cita. Como o identificador é o hash do vetor, quem quisesse plantar teria de já
  conhecer o que está plantando.

Em claro ficam só a apresentação (`/hello`: identidade do aparelho, nome do usuário, versão e
horário — o mesmo que o beacon já anuncia) e o identificador do inventário na query, necessário
para o servidor saber com qual chave conferir a assinatura antes de confiar em qualquer coisa.

**Versões.** A mudança de formato subiu o protocolo para 2. Pedido com outra versão recebe `426`
com a versão de quem responde, e a apresentação também traz a versão: nos dois sentidos, a tela
diz qual aparelho está com versão anterior ou mais nova e pede para atualizar os dois. Aparelho de
outra versão continua aparecendo na lista de descoberta — escondê-lo faria a pessoa procurar
defeito na rede.

### 5.10 Encerramento e campos do inventário

Encerrar o inventário é o marco que torna "não localizado" definitivo: sem ele não se sabe se o
item não foi achado ou se ninguém passou por lá ainda. É uma operação sobre a entidade
`inventario` (`encerrado_em`), com autor, que sincroniza como qualquer outra; reabrir é outra
operação, com o mesmo registro. Encerrado, o levantamento fica bloqueado em todos os aparelhos que
já souberem disso. Leituras feitas antes de saber — num aparelho longe da rede — não se perdem: o
log as aceita, e elas entram no resultado.

Os campos do inventário (nome, ano, EDs excluídos, encerramento) convergem por last-writer-wins
pelo HLC, com o vencedor guardado em `campos_inventario` (esquema v2). Até a v1 a operação era
aplicada sem comparar: uma antiga chegando depois desfazia a mais nova — com o encerramento, isso
reabriria um inventário encerrado. Não há registro de conflito aqui, porque não há o que a pessoa
decidir.

### 5.11 Entrada por link e pedido de entrada

O QR code resolve quem está ao lado. Para quem está a um prédio de distância, o convite vai por
link — e é aí que a chave de sincronização deixa de poder viajar junto.

**O link não leva a chave.** Ele identifica o inventário e o aparelho de origem, nada mais:

```
https://guilhermefeitosa66.github.io/slap-mobile/entrar#v=2&id=<uuid>&n=<nome>&a=<ano>&d=<aparelho>
```

Um link encaminhado por engano, reencaminhado adiante ou deixado num grupo de mensagens não dá
acesso a nada. A chave só é entregue depois que uma pessoa, no aparelho de origem, toca em
"Aceitar".

**Por que um endereço do site e não um esquema próprio.** Com `slapmobile://` o link daria erro em
quem não tem o aplicativo instalado. Sendo o endereço do site do projeto (App Link, `autoVerify` no
manifesto), quem não tem o aplicativo cai numa página que explica o que é aquilo e oferece o APK. O
esquema próprio continua existindo como reserva, para o caso de o Android não ter conseguido
verificar o App Link.

**Por que os dados vão no fragmento.** O fragmento (`#`) nunca é enviado ao servidor. Mesmo que
alguém abra o link no navegador, o GitHub Pages não vê nos registros dele o identificador do
inventário nem o nome do campus. O go_router preserva o fragmento em `GoRouterState.uri`, e o
Android entrega o endereço como `path?query#fragment` — rota inicial com o aplicativo fechado,
`pushRouteInformation` com ele aberto (daí o `launchMode="singleTop"`). A leitura aceita os mesmos
parâmetros na query, como tolerância a aplicativo de mensagens que reescreve endereços.

**Pedido de entrada.** Quem abre o link encontra o aparelho de origem pela descoberta e envia:

```
POST /inventario/pedido?inventario={id}  → {token, dispositivo, usuário, matrícula, pública efêmera}
```

É a **única rota não assinada** do protocolo, porque a chave que a assinaria é exatamente o que
está sendo pedido. O que autoriza não é criptografia: é uma pessoa. O pedido aparece como diálogo
sobre qualquer tela — o `OuvintePedidos` fica acima do `Navigator`, no `builder` do
`MaterialApp.router`, e por isso não depende de qual tela está aberta — dizendo quem está pedindo e
de qual aparelho. A requisição fica aberta até a resposta; sem ela, **caduca em um minuto**. O
token é de uso único: um pedido aceito não pode ser reapresentado por quem estava ouvindo a rede.

**Entrega da chave.** O canal cifrado de sempre deriva da própria `chave_sync`, que quem está
entrando ainda não tem — ele não serve para entregá-la. No aceite, os dois lados fazem um acordo
Diffie-Hellman com pares de chaves criados na hora, trocam só a parte pública e chegam ao mesmo
segredo sem que ele trafegue; dele sai, por HKDF, a chave AES-256-GCM que envelopa a `chave_sync`.
A derivação inclui o inventário, o token e as duas públicas, de modo que a chave combinada não
serve para outro pedido. Os pares são descartados em seguida: quem gravou a rede não decifra o
pedido nem mais tarde.

A curva é a **P-256 (`prime256v1`), e não a X25519** da proposta original: o `pointycastle`, já
usado aqui para o AES-GCM, não oferece X25519, e trazer uma segunda biblioteca de criptografia só
por causa dela deixaria duas implementações para auditar no lugar de uma. A chave pública recebida
é conferida contra a equação da curva antes do acordo, o que barra o ataque de curva inválida.

**O que isto não resolve.** Um atacante que consiga se pôr no meio da conversa na mesma rede local
pode trocar as duas públicas e ler a entrega — o acordo é anônimo, como o resto do transporte (ver
§5.9). O que o barra é o aceite: quem compartilha vê o nome e o aparelho de quem pede e recusa o
que não reconhece.

**O mesmo aceite vale para o QR code.** O QR continua carregando a chave — quem o mostra está com a
pessoa ao lado —, mas quem o lê também envia o pedido, e a chave que ele usa é a que vem do aceite.
Um só fluxo de entrada, dois jeitos de chegar a ele.

**Enquanto isso, do lado de quem compartilha.** A folha de compartilhar liga o servidor e o anúncio
na rede, e o anúncio continua por alguns minutos depois que ela fecha — a sequência real é "mando o
link, guardo o celular, a pessoa abre a mensagem". O que não dá para contornar é o Android encerrar
o processo em segundo plano; por isso a folha avisa, em uma linha, que os dois aparelhos precisam
estar na mesma rede Wi-Fi e que o aplicativo deve ficar aberto até o outro entrar.

**O que o site precisa servir** (ver `tool/gerar_site.py`): a página `/slap-mobile/entrar`, que
explica o convite e oferece o APK a quem não tem o aplicativo, e o
`/.well-known/assetlinks.json` com a impressão digital SHA-256 da chave de release, sem o qual o
Android não verifica o App Link e oferece o seletor de aplicativos em vez de abrir direto.

---

## 6. Velocidade

A spec §12 e §49 colocam velocidade como requisito de primeira ordem. As decisões que a
sustentam:

- **Configuração pegajosa**, herdada do SLAP: sala, estado, situação e responsável são
  definidos uma vez e aplicados às leituras seguintes. Uma leitura = zero toques na tela.
  A configuração fica na tabela `config` do aparelho e sobrevive ao Android encerrar o
  aplicativo, que reabre direto no levantamento — com a lista e o painel embaixo, para o
  voltar funcionar como de costume. Depois de 4 h sem ler (`ultima_leitura.<inventário>`,
  gravada a cada leitura, do campo ou da câmera; outras operações do aparelho não contam), a
  sala é confirmada antes da leitura seguinte: ao abrir o levantamento, ao voltar o
  aplicativo ao primeiro plano e antes de gravar. A câmera não grava com a sala vencida:
  fecha, e o levantamento pergunta. Um "Regravar" pendente cai quando a pergunta aparece:
  a leitura foi feita na sala antiga e não vai para a nova. Uma marca no futuro (a data do
  aparelho estava adiantada e foi corrigida) não conta, e sem outra a sala é confirmada.
  Bancos anteriores à marca a preenchem uma vez, na primeira consulta, com a última
  operação de patrimônio do aparelho no log. Essa primeira conta ainda inclui edições e
  desfazer, não só leituras; aceito, porque acontece uma vez e só em bancos antigos.
- **Busca indexada local**, sem rede no caminho da leitura.
- **Áudio pré-carregado**: os três sons ficam decodificados em memória; o feedback sai junto
  com a leitura, não depois dela.
- **Gravação assíncrona**: o som e o retorno visual não esperam o commit no SQLite.
- **Importação em isolate**, com transação única e statement preparado, para não travar a UI.
  Ler o XLSX, montar a prévia e gravar rodam fora da thread de interface; a gravação abre uma
  segunda conexão SQLite no isolate (WAL permite ler enquanto isso, e `busy_timeout` evita erro
  se as duas escreverem juntas) e informa o progresso a cada 250 itens. Falha no meio desfaz a
  transação inteira.
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
