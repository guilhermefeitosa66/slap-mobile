# Chave de assinatura

O Android só instala uma atualização se ela vier assinada com a **mesma chave** da versão já
instalada. Sem a chave, não sai atualização: quem tem o aplicativo precisa desinstalar e instalar
de novo — e desinstalar apaga o banco local, com todo inventário que ainda não foi sincronizado.

Por isso a chave é gerada uma vez, guardada com cópia, e **nunca** trocada.

## Onde ela está e quem tem acesso

Preencha depois de gerar e de guardar as cópias. Aqui vai o **lugar**, nunca a senha, o alias ou o
arquivo.

| | |
|---|---|
| Keystore principal | _a preencher — computador e pasta (fora do repositório)_ |
| Cópia 1 | _a preencher — ex.: pendrive cifrado guardado em ..._ |
| Cópia 2 | _a preencher — ex.: anexo no cofre de senhas da equipe_ |
| Senha e alias | _a preencher — cofre de senhas, separado do arquivo_ |
| Quem tem acesso | _a preencher — nomes_ |
| Última conferência das cópias | _a preencher — data_ |
| Impressão digital SHA-256 do certificado | _a preencher — é pública; ver [Conferir](#conferir-a-assinatura)_ |

## Gerar (uma vez só)

Na máquina de quem vai guardar a chave — **nunca no CI**:

```bash
tool/gerar_chave_release.sh
```

O script pergunta o alias, a senha (duas vezes, sem mostrar na tela) e se a senha fica gravada no
`key.properties`; depois o `keytool` pergunta nome e organização, que vão no certificado e são
públicos. Ele então:

- cria `~/.slap-chaves/slap-release.jks` (RSA 4096, PKCS12, validade de 10 000 dias), com
  permissão só para o dono. Outra pasta: `SLAP_DIR_CHAVES=/caminho tool/gerar_chave_release.sh`;
- escreve `android/key.properties` com o caminho absoluto do keystore, com permissão `600`;
- recusa rodar em CI, sobrescrever um keystore ou um `key.properties` existente, criar o keystore
  dentro do repositório ou escrever o `key.properties` se o `.gitignore` não o barrar.

Nada de senha ou alias é impresso.

**Senha fora do disco.** Respondendo "não" à pergunta da senha, o `key.properties` fica só com o
caminho e o alias, e o build lê a senha da variável `SLAP_SENHA_CHAVE`:

```bash
read -rs SLAP_SENHA_CHAVE && export SLAP_SENHA_CHAVE
flutter build apk --release --split-per-abi
```

## Guardar as cópias

Antes da primeira release, e não depois:

1. **Duas cópias fora do computador de trabalho**, em lugares diferentes — por exemplo, um pendrive
   cifrado guardado na instituição e um anexo no cofre de senhas da equipe (Bitwarden, 1Password,
   KeePassXC).
2. **Senha e alias num cofre de senhas**, separados do arquivo: quem acha o pendrive não assina
   nada sem a senha.
3. **Conferir que a cópia abre**, noutra máquina: com a cópia e sem nenhum `key.properties`,

   ```bash
   tool/gerar_chave_release.sh --existente /caminho/da/copia/slap-release.jks
   ```

   confere senha e alias contra o arquivo e escreve o `key.properties`. É o mesmo comando para
   montar um computador novo.
4. Preencher a [tabela acima](#onde-ela-está-e-quem-tem-acesso).

## Como o build usa a chave

`android/app/build.gradle.kts` lê `android/key.properties` quando ele existe:

- **com o arquivo**, o build de release sai assinado com a chave de release;
- **sem o arquivo**, sai com a chave de debug e o Gradle avisa — clonar e compilar continua
  funcionando para qualquer pessoa, mas esse APK não serve para publicar: não atualiza a versão
  publicada.

O `.gitignore` barra `key.properties`, `*.jks` e `*.keystore`. O CI só gera APK de debug, e a chave
não entra nos segredos do GitHub.

## Conferir a assinatura

Num APK gerado, com o `apksigner` do Android SDK (`build-tools/<versão>/apksigner`):

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

A linha `Signer #1 certificate SHA-256 digest` é a impressão digital do certificado. Ela é pública
— qualquer um a lê no APK — e deve ser **sempre a mesma**. Anote-a na tabela; publique-a junto
das releases, para quem baixa poder conferir. `CN=Android Debug` no certificado quer dizer que o
`key.properties` não foi encontrado.

`tool/gerar_release.sh` faz essa conferência sozinho (ver [processo de release](release.md)).

## Play Store: chave de upload e chave de assinatura

Na Play Store, com a Assinatura de apps do Google Play (obrigatória para aplicativo novo), existem
duas chaves:

- a **chave de assinatura do app**, com que o Google assina o que entrega aos aparelhos;
- a **chave de upload**, com que se assina o `.aab` enviado ao Play Console.

A decisão é tomada **uma vez**, ao cadastrar o aplicativo no Play Console:

- **Deixar o Google gerar a chave de assinatura** (o padrão). A chave daqui vira só a de upload, e
  se ela for perdida o Play Console permite trocá-la. Mas o APK da Play Store e o do GitHub ficam
  com assinaturas diferentes: quem instalou por um canal não atualiza pelo outro sem desinstalar.
- **Enviar a chave daqui como chave de assinatura** (opção "usar minha própria chave", exportada
  cifrada com a ferramenta que o próprio Play Console indica). Os dois canais ficam com a mesma
  assinatura, e o Google passa a guardar uma cópia. O `.aab` então é enviado com uma chave de
  upload separada, gerada à parte.

**Recomendação: a segunda.** Neste aplicativo, desinstalar apaga o trabalho que ainda não foi
sincronizado; poder trocar do APK do GitHub para a Play Store sem desinstalar vale o passo a mais.

## Se algo der errado

- **A chave foi perdida.** Pelo GitHub, não há atualização possível: cada pessoa exporta uma cópia
  do seu trabalho (*Ajustes → Exportar cópia*, ver [cópia de segurança](copia-de-seguranca.md)),
  desinstala, instala a versão nova e restaura a cópia. Na Play Store, se a chave perdida era só a
  de upload, o Play Console permite pedir a troca.
- **A chave vazou** (arquivo e senha juntos). Na Play Store, pedir a troca da chave de upload. Para
  o GitHub, o esquema de assinatura v3 (Android 9 ou mais novo) permite rotacionar a chave com
  `apksigner rotate`: a versão seguinte sai com uma chave nova, autorizada pela antiga. É um passo
  delicado — planejar com a documentação do `apksigner` antes, publicar a impressão digital nova e
  avisar quem instala.
- **Nunca**: gerar uma chave nova "porque a senha se perdeu" e publicar com ela; colocar a chave,
  a senha ou o alias em commit, issue, chat, log ou segredo do CI.
