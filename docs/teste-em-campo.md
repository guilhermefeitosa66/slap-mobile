# Teste em campo

Os testes automatizados validam a convergência e o transporte em localhost. O que só um campus
valida é a **rede real**: se os aparelhos se acham, se conversam, quanto demora e quanto gasta de
bateria. Este é o roteiro da issue #14, com o que observar em cada passo e uma ficha para
registrar. A issue fecha quando ele rodar inteiro num campus, não em bancada.

## Preparar

**Aparelhos.** Três ou mais celulares Android — de marcas e versões diferentes, se possível; um
iPhone, se houver. Anote modelo e versão do sistema de cada um na [ficha](#ficha).

**APK.** De preferência o assinado com a chave de release ([release.md](release.md)): um APK
assinado com a chave de debug não é atualizado pelo publicado depois, e desinstalar apaga o que
foi levantado. Leve também, instaladas num aparelho à parte ou prontas no computador, duas
variantes para isolar cada via de descoberta, se precisar:

```bash
flutter build apk --release --split-per-abi --dart-define=SLAP_DESCOBERTA=beacon
flutter build apk --release --split-per-abi --dart-define=SLAP_DESCOBERTA=mdns
```

**Instalar.** A partir de 30 de setembro de 2026, celulares Android certificados no Brasil só
instalam pelo caminho normal apps de desenvolvedor registrado no Google (ver
[release.md](release.md#verificação-de-desenvolvedor-do-android)). Para o teste, `adb install` de um
computador funciona sempre; a conta gratuita de distribuição limitada cobre até 20 aparelhos.

**Dados.** A planilha real do SUAP no aparelho que vai criar o inventário.

**Bateria.** Carregue todos, e anote a porcentagem e a hora no começo.

**Rede.** A rede Wi-Fi que os servidores de fato usam no campus. Anote o nome e o tipo
(institucional, eduroam, visitantes).

## Roteiro

### 1. Todos na rede do campus

Conecte todos ao mesmo Wi-Fi. Em cada um, crie um inventário qualquer de teste e abra
**Sincronizar**. Em até 30 segundos, cada aparelho deve listar os outros, com a linha
**"Encontrado por …"**:

- `mDNS e anúncio na rede` — as duas vias funcionam nesta rede;
- só `mDNS` ou só `anúncio na rede` — uma delas é barrada; anote qual;
- lista vazia — ver [Se ninguém aparece](#se-ninguém-aparece).

Apague o inventário de teste depois.

### 2. Criar e entrar

No aparelho A: **Novo**, importar a planilha real. Anote quantos patrimônios e quanto tempo a
importação levou.

Nos aparelhos B e C: A mostra o QR code (**Sincronizar → ícone de QR code**), e cada um lê pelo
ícone de QR code da lista de inventários. Anote quanto tempo levou até o inventário aparecer
completo em cada um.

### 3. Levantar sem contato

Cada pessoa levanta uma sala diferente, sem sincronizar no meio. Anote quantas leituras cada um
fez. Deixe a tela ligada o tempo todo, como no uso real.

### 4. Sincronizar todos com todos

De volta, em cada aparelho: **Sincronizar** e sincronizar com cada um dos outros. O resultado de
cada troca mostra o que foi recebido e enviado e **quanto tempo levou** (`… · 1,4 s`). Anote.

### 5. Conferir os números

No painel de cada aparelho: porcentagem verificada e os três grupos — **Itens OK**,
**Divergentes**, **Não localizados**. **Os três aparelhos têm de mostrar os mesmos números.**

### 6. Forçar um conflito

Escolha um patrimônio. Duas pessoas o conferem **em salas diferentes**, sem sincronizar antes.
Depois sincronizem. Esperado:

- o conflito aparece nos dois aparelhos (aviso no painel e na tela de sincronização);
- resolvido num deles e sincronizado de novo, ele some em **todos** — inclusive no terceiro.

### 7. Comparar os relatórios

Em cada aparelho, gere os relatórios em **CSV** e passe para um computador. O nome do arquivo tem a
hora, o conteúdo não; compare o conteúdo:

```bash
sha256sum aparelho-a/*.csv aparelho-b/*.csv aparelho-c/*.csv
```

Relatórios do mesmo grupo têm de ter a mesma soma nos três aparelhos.

### No fim

Anote a bateria de cada aparelho e a hora. Em **Configurações → Bateria → Uso por app**, anote
quanto o SLAP consumiu.

## Se ninguém aparece

Duas causas possíveis, com saídas diferentes:

1. **Isolamento de cliente** — a rede não deixa um aparelho falar com outro. Não há solução no
   aplicativo: usa-se um ponto de acesso de um dos celulares.
2. **Multicast barrado** — os aparelhos se falam, mas os anúncios não circulam.

Para separar: veja o IP de cada aparelho (**Configurações → Wi-Fi → rede conectada**) e, com um
aplicativo de rede (Fing, PingTools), faça um ping de um para o outro.

- O ping **não responde**: isolamento de cliente.
- O ping **responde**, mas o SLAP não lista ninguém: multicast barrado. Teste as variantes
  `beacon` e `mdns` — pode ser que uma passe.

Em qualquer caso, repita o passo 1 com um celular compartilhando a internet (ponto de acesso) e os
outros conectados nele: se funcionar ali, o problema é da rede do campus. Anote o que o setor de
TI disser sobre a rede.

## Ficha

Copie para um comentário na issue #14 e preencha. Use só o primeiro nome de quem participou.

```markdown
**Campus / data:**
**Rede:** nome — tipo (institucional / eduroam / visitantes)

| Aparelho | Modelo | Android | Bateria início → fim | Uso do SLAP (Config. → Bateria) |
|---|---|---|---|---|
| A | | | % → % | % |
| B | | | % → % | % |
| C | | | % → % | % |

**1. Descoberta**
- A vê B por: ______  A vê C por: ______  B vê C por: ______
- Isolamento de cliente? sim / não (ping: responde / não responde)
- Ponto de acesso de celular, se usado: funcionou? sim / não

**2. Criar e entrar**
- Patrimônios na planilha: ___  Tempo de importação: ___
- Tempo até o inventário completo em B: ___  em C: ___

**3. Levantamento:** leituras em A: ___ B: ___ C: ___

**4. Sincronização** (tempo mostrado em cada troca)
- A↔B: ___  A↔C: ___  B↔C: ___

**5. Números do painel**

| | % | OK | Divergentes | Não localizados |
|---|---|---|---|---|
| A | | | | |
| B | | | | |
| C | | | | |

**6. Conflito:** apareceu nos dois? ___  Resolvido, sumiu nos três? ___

**7. Relatórios CSV:** somas iguais nos três? ___

**Observações** (travamentos, mensagens de erro, o que confundiu quem usou):
```
