# Política de privacidade do SLAP Mobile

_Última atualização: 24 de setembro de 2026._

O SLAP Mobile é um aplicativo de inventário patrimonial, software livre
([código-fonte](https://github.com/guilhermefeitosa66/slap-mobile)). Esta página diz quais dados ele
guarda, para onde eles vão e por quê.

## Em resumo

- Os dados ficam **no seu aparelho**.
- Eles só saem para **outros aparelhos do mesmo inventário**, direto pela rede local e cifrados, ou
  num arquivo que **você** decide gerar e enviar.
- Não há servidor, conta, anúncio nem rastreamento. Quem mantém o aplicativo **não recebe nenhum
  dado** dele.
- Duas exceções, e nenhuma delas leva dado do inventário:
  - a biblioteca do Google que lê códigos de barras envia ao Google dados técnicos de
    funcionamento dela — nunca as imagens nem os códigos lidos. Ver
    [Leitura de códigos no Android](#leitura-de-códigos-no-android);
  - ao abrir, o aplicativo pergunta ao GitHub qual é a última versão publicada, para avisar quando
    a sua está desatualizada. Ver [Verificação de versão](#verificação-de-versão).

## O que o aplicativo guarda no aparelho

- **Os dados do inventário**, importados da planilha do SUAP que você escolhe: tombo, código de
  barras, descrição, sala, valor, estado de conservação, situação e o nome do servidor responsável
  por cada bem.
- **O que o levantamento registra**: quais itens foram conferidos, em que sala, quando, e por quem
  — o nome, e a matrícula se você a informar, que você cadastra ao abrir o aplicativo pela primeira
  vez e pode mudar em *Ajustes*. Cada alteração no inventário leva esse nome, e ele aparece para os
  colegas do inventário e nos relatórios.
- **Um identificador do aparelho**, sorteado na primeira vez que o aplicativo abre. Serve para
  numerar as alterações na sincronização. Não vem do hardware nem de nenhum identificador do
  sistema, e troca se você usar *Ajustes → Gerar nova identidade*.
- **Suas preferências**: sons, vibração, tela ligada.

Tudo fica no armazenamento privado do aplicativo e **fora do backup automático** do sistema (do
Android e do iCloud). Para apagar: *apagar o inventário* no aplicativo, ou desinstalá-lo.

## Para onde os dados vão

**Outros aparelhos do mesmo inventário.** A sincronização é feita direto entre os celulares, pela
rede local, sem servidor e sem passar pela internet. Só participa quem entrou no inventário — pelo
QR code ou por um convite aceito; todo o conteúdo trocado vai cifrado com a chave do inventário
(AES-256-GCM) e ninguém sem ela consegue ler ou alterar.

**O link de convite não contém a chave do inventário.** Ele leva apenas o identificador do
inventário, o nome, o ano e o identificador do aparelho que compartilhou — nenhum dado de
patrimônio, nenhum nome de pessoa. Um link encaminhado a quem não devia não dá acesso a nada: a
chave só é entregue depois que alguém, no aparelho que compartilhou, aceita o pedido. Esses dados
vão depois do `#` do endereço, a parte que o navegador **não envia ao servidor**: abrir o link
sem o aplicativo instalado leva a uma página do projeto que não recebe nem registra nada disso.

**O pedido de entrada.** Quando você abre um convite, o seu aparelho envia ao aparelho que
compartilhou o **seu nome**, a **sua matrícula** (se você a informou) e o **identificador do seu
aparelho**, para que a pessoa do outro lado saiba quem está pedindo e decida. O pedido não sai da
rede local, vale um minuto e serve uma vez só. Sem o aceite, nada mais é trocado; com ele, a chave
do inventário chega cifrada com um segredo combinado na hora entre os dois aparelhos, que é
descartado em seguida.

**A rede local, enquanto você sincroniza ou compartilha.** Para os colegas acharem o seu
aparelho, ele se anuncia na rede Wi-Fi com o **nome que você informou** e o **identificador do
aparelho**. Esse anúncio não é cifrado: outros aparelhos conectados à mesma rede podem ver esses
dois dados — e só eles, nenhum dado do inventário. O anúncio para pouco depois de você sair da
tela; o
aparelho segue atendendo a sincronização até o aplicativo ser fechado, e quem o procurar
diretamente na rede ainda consegue ver o nome e o identificador.

**Arquivos que você gera.** Relatórios (XLSX ou CSV) e cópias de segurança só saem do aplicativo
pela janela de salvar ou compartilhar do sistema, para onde você escolher. A partir daí, seguem as
regras de onde você os guardou.

### Leitura de códigos no Android

No Android, a leitura de códigos de barras e de QR code usa o **ML Kit**, uma biblioteca do Google
que roda dentro do aplicativo. O reconhecimento é feito no próprio aparelho: as imagens da câmera e
os códigos lidos **não saem dele**.

A biblioteca, porém, envia ao Google dados técnicos sobre o funcionamento dela — modelo do
aparelho, versão do Android, nome e versão do aplicativo, um identificador da instalação que não
identifica você nem o aparelho, tempos de resposta e códigos de erro —, com conexão cifrada, para o
Google medir e melhorar a biblioteca. Quem mantém o SLAP Mobile não tem acesso a esses dados. Os
detalhes estão na
[divulgação de dados do ML Kit](https://developers.google.com/ml-kit/android-data-disclosure).

No iPhone, a leitura usa o recurso do próprio sistema, que não envia nada.

## Verificação de versão

O aplicativo é instalado por arquivo APK, fora da loja: nada avisaria quem está com uma versão
antiga, e uma versão antiga pode ter um defeito já corrigido. Por isso, **ao abrir**, ele consulta

```
https://api.github.com/repos/guilhermefeitosa66/slap-mobile/releases/latest
```

e compara o número da última versão publicada com a instalada. Havendo versão mais nova, aparece
uma faixa com um botão que leva à página de instalação.

**O que essa consulta envia:** nada além do próprio pedido HTTP. Nenhum dado do inventário,
nenhum identificador do aparelho, nenhum nome. Como em qualquer acesso à internet, o GitHub
registra o endereço IP de onde o pedido saiu e o tipo de aplicativo que pediu; é o mesmo que
aconteceria ao abrir a página do projeto no navegador. Quem mantém o SLAP Mobile não recebe nada
dessa consulta nem tem acesso a esses registros.

**Como desligar:** em **Ajustes → Atualizações → Avisar de versão nova**. Desligada, o aplicativo
não faz essa consulta, e nenhuma outra sai dele por conta própria — resta só a sincronização, que
é local e só acontece quando você manda.

Se a consulta falhar — sem internet, com o GitHub fora do ar — o aplicativo abre normalmente e
não avisa nada. O levantamento não depende dela.

## Permissões

- **Câmera** — para ler os códigos de barras dos patrimônios e o QR code que dá entrada num
  inventário. Nenhuma foto ou vídeo é gravado ou enviado. Ela só é pedida quando você abre a
  câmera, e o aplicativo funciona sem ela com um leitor de código externo.
- **Rede local** — para achar os outros aparelhos do inventário e sincronizar com eles. No
  Android, aparece como acesso à rede e à internet, que é a permissão técnica para usar a rede. O
  aplicativo só conversa com aparelhos da mesma rede local, além das duas exceções acima: o ML Kit
  e a verificação de versão.

O aplicativo **não** pede localização, contatos, microfone, fotos nem acesso aos seus arquivos: a
planilha e as cópias são abertas pela janela de arquivos do sistema, só o arquivo que você escolher.

## Seus direitos

Quem mantém o aplicativo não guarda nenhum dado seu, então não há o que consultar ou apagar do
lado de cá. Os dados do inventário, inclusive os nomes dos responsáveis pelos bens, vêm do SUAP e
são tratados pela instituição que realiza o inventário; pedidos sobre eles, nos termos da Lei Geral
de Proteção de Dados (Lei 13.709/2018), vão a ela. O que está no seu aparelho você apaga quando
quiser, como descrito acima.

O aplicativo é uma ferramenta de trabalho para servidores públicos e não se destina a crianças.

## Mudanças e contato

Qualquer mudança nesta política é publicada nesta página, com a data no topo, e o histórico fica
no [repositório](https://github.com/guilhermefeitosa66/slap-mobile/commits/main/docs/privacidade.md).
Dúvidas: abra uma [issue](https://github.com/guilhermefeitosa66/slap-mobile/issues) no GitHub.
