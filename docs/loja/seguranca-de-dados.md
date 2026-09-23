# Formulários de privacidade das lojas

Respostas para a **Segurança dos dados** do Play Console e a **Privacidade do app** da App Store,
tiradas do que o código faz. A [política de privacidade](../privacidade.md) diz o mesmo em
linguagem de usuário; se uma mudar, a outra muda junto.

URL da política, para os dois formulários:
`https://guilhermefeitosa66.github.io/slap-mobile/privacidade/` (publicada pelo workflow
`.github/workflows/pages.yml`).

## O que sai do aparelho, e o que conta

| Fluxo | Sai do aparelho? | Declarar? |
|---|---|---|
| Inventário, leituras, nome e matrícula de quem conferiu — sincronização | Sim, para os aparelhos do mesmo inventário | **Não**: cifrado de ponta a ponta (AES-256-GCM, chave só no QR code do inventário, sem intermediário). A Play dispensa dado que ninguém além de quem envia e quem recebe consegue ler. |
| Relatórios e cópias de segurança | Só quando a pessoa salva ou compartilha | **Não**: é a pessoa que envia, pelo seletor do sistema, para onde escolher. |
| Nome e identificador do aparelho no anúncio da rede local (mDNS, beacon, `/hello`) | Sim, em claro, para a rede local | **Zona cinza** — ver abaixo. |
| Diagnóstico do ML Kit (só Android) | Sim, para o Google | **Sim** — ver abaixo. |
| Imagens da câmera e códigos lidos | Não | Não. |

### ML Kit (Android)

A leitura de código no Android usa o ML Kit do Google, embutido (`com.google.mlkit:barcode-scanning`,
padrão do `mobile_scanner`). Pela
[divulgação do próprio Google](https://developers.google.com/ml-kit/android-data-disclosure), ele
envia informações do aparelho e do app, métricas de desempenho e um identificador da instalação,
para diagnóstico e análise de uso, cifrado em trânsito e sem compartilhar com terceiros. Imagens e
resultados não saem do aparelho.

**Antes de preencher, abra a página do Google e siga a tabela dela para a API de leitura de
código de barras** — é ela que vale, e pode ter mudado.

### O anúncio na rede local

Enquanto a tela de sincronização está aberta, o aparelho anuncia o nome da pessoa e o identificador
do aparelho em claro na rede Wi-Fi, e o servidor local responde os dois a quem pedir. Não vai para
servidor nenhum nem para quem mantém o app — mas a definição da Play é "transmitir dados para fora
do aparelho", e a isenção de criptografia de ponta a ponta não cobre esse anúncio.

Recomendação: **declarar**, até o anúncio deixar de levar o nome (há uma tarefa sugerida para isso).
Declarar a mais é seguro; declarar a menos pode tirar o app da loja.

## Play Console — Segurança dos dados

**Coleta e segurança**

| Pergunta | Resposta |
|---|---|
| O app coleta ou compartilha algum dos tipos de dados do usuário exigidos? | **Sim** (ML Kit; e o anúncio na rede local, se declarado) |
| Todos os dados coletados são criptografados em trânsito? | **Não**, se o anúncio na rede local for declarado (ele vai em claro); **Sim**, se não for — o ML Kit usa HTTPS |
| Como os usuários criam uma conta? | O app não permite criar conta |
| Os usuários podem pedir a exclusão dos dados? | Não: quem mantém o app não recebe dado nenhum. O que está no aparelho some ao apagar o inventário ou desinstalar. |

**Tipos de dados** — conferir com a tabela do Google para o ML Kit:

| Tipo | Coletado | Compartilhado | Temporário | Obrigatório | Finalidade |
|---|---|---|---|---|---|
| Informações e desempenho do app → Diagnóstico | Sim (ML Kit) | Não | Não | Sim | Análise |
| Dispositivo ou outros IDs | Sim (ML Kit; e o identificador do aparelho no anúncio) | Não | Não | Sim | Análise (ML Kit); Funcionalidade do app (anúncio) |
| Informações pessoais → Nome | Sim, se o anúncio for declarado | Não | Não | Sim (o app pede o nome na primeira abertura) | Funcionalidade do app |

Nada de localização, contatos, fotos e vídeos (a câmera não grava), arquivos, mensagens,
histórico de navegação, informações financeiras ou de saúde.

**Permissões**, para o formulário e para a revisão:

- `CAMERA` — ler os códigos de barras dos patrimônios e o QR code de entrada num inventário.
  Nenhuma imagem é gravada ou enviada; o app funciona sem ela com leitor de código externo.
- `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE` — achar os outros aparelhos do
  inventário na rede local (mDNS e multicast) e sincronizar com eles, sem servidor.

## App Store — Privacidade do app

A Apple considera coleta o dado que sai do aparelho de um jeito que o desenvolvedor ou parceiros
dele possam acessar. No iPhone a leitura de código usa o Vision, do próprio sistema, sem ML Kit; a
sincronização é cifrada entre os aparelhos; e o anúncio na rede local não chega ao desenvolvedor.

Resposta: **Dados não coletados.**
