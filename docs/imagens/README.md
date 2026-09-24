# Capturas de tela

As imagens do README, do site e do [manual](../manual.md) (`tool/gerar_site.py`). Diferente das capturas da loja em
[`../loja/capturas/`](../loja/capturas/), geradas por teste golden com dados fictícios, estas
vêm do emulador com um inventário real — só os **nomes de servidores e a matrícula são
fictícios**, porque a planilha do SUAP traz nome e matrícula de pessoas.

Cada arquivo tem o nome que `CAPTURAS`, em `tool/gerar_site.py`, espera:

| Arquivo | Tela |
|---|---|
| `identidade.png` | primeira abertura: nome e matrícula |
| `inventarios.png` | lista de inventários |
| `importacao.png` | conferência das colunas da planilha |
| `painel.png` | painel do inventário |
| `compartilhar.png` | folha de compartilhar: QR code ou link |
| `configuracao.png` | configuração das leituras |
| `levantamento.png` | levantamento com leituras feitas |
| `camera.png` | leitura pela câmera |
| `sincronizacao.png` | sincronização |
| `itens.png` | todos os itens |
| `detalhe.png` | detalhe de um patrimônio |
| `relatorios.png` | relatórios |

## Como refazer

1. **Planilha com nomes fictícios.** A partir da exportação real do SUAP, troque o nome da
   pessoa na coluna `CARGA ATUAL` (a parte antes do parêntese) por um nome inventado, mantendo o
   resto da célula; um nome fictício por nome real, para as sugestões de responsável continuarem
   fazendo sentido. Não versione nem a planilha real nem a modificada.
2. **Emulador em tema claro**, com a barra de status em modo de demonstração, para todas as
   capturas terem o mesmo relógio e bateria cheia:

   ```bash
   adb shell settings put global sysui_demo_allowed 1
   adb shell am broadcast -a com.android.systemui.demo -e command enter
   adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1000
   adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
   adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
   adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
   ```

   Ao terminar: `adb shell am broadcast -a com.android.systemui.demo -e command exit`.
3. **Identidade fictícia** na primeira abertura (ou em Ajustes), por exemplo "Ana Souza",
   matrícula "2091234".
4. Importe a planilha num inventário novo, faça algumas leituras (registrada, já verificada, não
   localizada; mude de sala uma vez para haver divergência) e percorra as telas da tabela.
   Capture cada uma com `adb exec-out screencap -p > <nome>.png`, numa pasta fora do
   repositório.
5. Reduza e grave em `docs/imagens/`:

   ```bash
   python3 tool/reduzir_capturas.py <pasta com as capturas>
   ```

6. Confira o resultado gerando o site (`python3 tool/gerar_site.py _site`) e olhando o README.
