# Capturas de tela

As imagens do README, do site e do [manual](../manual.md). Como as da loja em
[`../loja/capturas/`](../loja/capturas/), saem de um teste golden com dados de demonstração
(`test/capturas/cenario.dart`, nomes fictícios), no tamanho do iPhone de 6,3 polegadas
(1206 × 2622), com barra de status e indicador de início. O site as põe numa moldura de celular.

Cada arquivo tem o nome que `CAPTURAS`, em `tool/reduzir_capturas.py`, espera:

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
| `filtros.png` | filtros da lista de itens |
| `detalhe.png` | detalhe de um patrimônio |
| `relatorios.png` | relatórios |

## Como refazer

```bash
flutter test --run-skipped --tags capturas --update-goldens test/capturas/site_test.dart
python3 tool/reduzir_capturas.py build/capturas-site 1206
```

O teste grava em `build/capturas-site/`; o script reduz a paleta e grava aqui. Telas que dependem
de câmera, rede ou seletor de arquivos usam dublês no próprio teste: a câmera mostra uma etiqueta
desenhada, a troca de dados encontra dois colegas fictícios e a importação lê
`docs/loja/planilha-demonstracao.xlsx`.

Para o site, copie as imagens para o repositório dele e rode `make capturas` e `make gerar` lá
(ver [desenvolvimento.md](../desenvolvimento.md#site)).
