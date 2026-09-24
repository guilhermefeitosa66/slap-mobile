# Instalar o SLAP Mobile fora da loja

Enquanto o aplicativo não está na Play Store, ele é instalado pelo arquivo APK publicado no GitHub.
Precisa de **Android 7.0 ou mais novo**.

## 1. Baixar

No celular, abra a página da
[versão mais recente](https://github.com/guilhermefeitosa66/slap-mobile/releases/latest) e toque no
arquivo:

- **`slap-…-arm64-v8a.apk`** — serve para praticamente todo celular dos últimos anos. Comece por
  ele.
- `slap-…-armeabi-v7a.apk` — só se o primeiro der "aplicativo não instalado" ou "incompatível":
  é para celulares antigos, de 32 bits.
- `slap-…-x86_64.apk` — emuladores e alguns Chromebooks.

## 2. Permitir a instalação

Ao abrir o arquivo baixado, o Android avisa que o aplicativo usado para abri-lo (o navegador, ou o
Arquivos) não tem permissão para instalar aplicativos desconhecidos:

1. Toque em **Configurações** no aviso.
2. Ative **Permitir desta fonte**.
3. Volte e toque em **Instalar**.

Os nomes mudam um pouco de fabricante para fabricante. A permissão pode ser desligada depois da
instalação, em **Configurações → Apps → Acesso especial → Instalar apps desconhecidos**. No
Android 7, a opção é **Configurações → Segurança → Fontes desconhecidas**.

Se o **Google Play Protect** pedir para analisar o aplicativo, pode enviar. Se avisar que não
conhece o aplicativo, a opção de instalar assim mesmo fica em **Mais detalhes**.

As versões publicadas saem de desenvolvedor registrado no Google — o que o Android exige no Brasil
a partir de 30 de setembro de 2026 — e instalam normalmente. Se o celular disser que o desenvolvedor
**não é verificado**, não use atalhos para contornar: avise numa
[issue](https://github.com/guilhermefeitosa66/slap-mobile/issues).

## 3. Conferir o arquivo (opcional)

Cada versão traz `SHA256SUMS.txt` com a soma de cada APK, e as notas da versão trazem a impressão
digital do certificado de assinatura — que é a mesma em todas as versões. Num computador:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```

## Atualizar

Baixe o APK da versão nova e instale **por cima** da que está no celular: os inventários ficam.

**Não desinstale para atualizar.** Desinstalar apaga do celular tudo o que ainda não foi
sincronizado com outro aparelho. Se o Android recusar a atualização — por exemplo, porque a
versão instalada veio de outro lugar —, antes de qualquer coisa sincronize com um colega e exporte
uma cópia (**Ajustes → Exportar cópia**); depois de reinstalar, restaure em
**Ajustes → Restaurar de uma cópia**.
