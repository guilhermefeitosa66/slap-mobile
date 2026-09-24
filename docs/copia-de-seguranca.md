# Cópia de segurança e identidade do aparelho

Se o celular for perdido ou formatado no meio de um inventário, o trabalho que só ele tinha some
— a não ser que tenha sido sincronizado com alguém. A cópia de segurança cobre esse caso.

## Como usar

- **Exportar** — *Ajustes → Exportar cópia* gera um arquivo `.slapcopia` com todos os inventários
  do aparelho; *Painel → ⋮ → Exportar cópia deste inventário* gera só aquele. O seletor do
  sistema pergunta onde guardar: computador, e-mail, drive. Guarde **fora do celular**.
- **Restaurar** — *Ajustes → Restaurar de uma cópia*. Antes de aplicar, a tela mostra de quem é a
  cópia, de quando, e quais inventários ela traz (e quais já estão no aparelho).

Restaurar **não apaga nada**: o que a cópia tem e o aparelho não, entra; o resto fica como está.
Restaurar a mesma cópia duas vezes não duplica nada. A restauração entra inteira ou não entra —
é uma transação só.

## O arquivo

É um banco SQLite com o mesmo esquema do aplicativo: inventários, dados do SUAP, log de operações,
contextos causais e conflitos (inclusive os já resolvidos). Ficam **de fora** a identidade do
aparelho, o relógio, as preferências e o registro de pares; vai só o nome de quem exportou e o
momento, para a pessoa reconhecer o arquivo.

A cópia é gerada com `VACUUM INTO`, que grava o estado confirmado mesmo com o aplicativo em uso,
numa segunda conexão fora da thread de interface.

Cópia de versão mais nova do aplicativo é recusada com orientação para atualizar. Cópia de versão
anterior é aceita: as tabelas lidas existem em todas as versões do esquema.

## A decisão: a identidade não viaja

Cada aparelho numera as próprias operações (`seq`) e tem uma identidade (`dispositivo_id`) gerada
na primeira execução. A sincronização inteira depende de um par `(identidade, seq)` apontar sempre
para a mesma operação: é o que a version vector conta, e o que diz a um par o que falta a outro.

Se a identidade fosse junto com a cópia, restaurar num aparelho novo enquanto o antigo continua em
uso — o celular não se perdeu, só foi trocado, ou a cópia foi aberta em dois — faria os dois
escreverem `(X, 101)` com operações diferentes. Cada par aceitaria a primeira que chegasse e
descartaria a outra achando que já a tinha. Perda silenciosa.

Por isso **restaurar não transforma o aparelho novo no antigo**. As operações da cópia entram como
se viessem de um terceiro pela sincronização — com a identidade de quem as escreveu, a numeração e
os contextos originais, a detecção de conflito intacta. O aparelho novo continua com a própria
identidade, e o que ele escrever depois sai em nome dele, já causalmente depois de tudo que a
cópia trouxe (por isso não gera conflito falso).

O resultado verificado pelos testes (`test/data/copia_seguranca_test.dart`): exportar, restaurar
num aparelho novo e sincronizar com os outros leva todos ao mesmo estado, com os conflitos
resolvidos continuando resolvidos.

## Quando a identidade é copiada por fora do aplicativo

O aplicativo não copia a identidade, mas o sistema poderia: o backup automático do Android e o do
iCloud restauram os dados do aplicativo inteiro num celular novo. Por isso:

- **Android** — `allowBackup="false"` e regras de extração (`res/xml/regras_de_backup.xml`) que
  excluem tudo do backup em nuvem e da transferência entre aparelhos.
- **iOS** — o banco é marcado como fora do backup do iCloud na abertura
  (`lib/core/backup_do_sistema.dart`, canal `slap/arquivos`).

Se ainda assim dois aparelhos passarem a escrever com a mesma identidade — cópia manual de pastas,
por exemplo —, a sincronização **detecta e recusa**, sem misturar nada:

- ao aplicar operações, a mesma posição `(identidade, seq)` com outra operação;
- em cada pedido e cada envio vai a última operação conhecida de cada aparelho (as "cabeças"), e o
  outro lado confere se tem a mesma naquela posição. Sem isso, dois clones que escreveram o mesmo
  número de operações nunca pediriam um ao outro a posição em disputa.

A mensagem explica o que aconteceu. A saída é **Ajustes → Gerar nova identidade** num dos dois
aparelhos: os inventários dele são apagados, a identidade é trocada, e ele entra de novo pelo QR
code, recebendo o que os outros têm. O que aquele aparelho fez depois da cópia e não chegou a
ninguém se perde — é o custo que a prevenção acima existe para evitar.

## Apagar a réplica e voltar

Relacionado, e corrigido junto: um aparelho que apaga um inventário e volta a ele pelo QR code
recupera o próprio trabalho pelos pares — antes, operações com a identidade do próprio aparelho
eram descartadas ao chegar, e a numeração recomeçava do 1, colidindo com as antigas que os pares
ainda guardavam. Agora:

- operação do próprio aparelho que não está no banco local é aplicada como qualquer outra;
- ao apagar, o maior `seq` usado fica guardado (`seq_minimo.<inventário>`), e a numeração
  continua dali;
- o pedido de sincronização conta, para o próprio aparelho, só a parte contígua da sequência, de
  modo que as operações antigas ainda faltantes voltam mesmo que ele já tenha escrito novas;
- entrar num inventário pelo QR code já sincroniza com o aparelho que forneceu o pacote.
