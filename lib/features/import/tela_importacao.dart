import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'importador.dart';
import 'leitor_planilha.dart';
import 'mapeamento.dart';

/// Importação da planilha, em três passos.
///
/// A confirmação do mapeamento aparece **sempre**, mesmo quando todas as
/// colunas foram reconhecidas. Um mapeamento errado aceito em silêncio
/// corrompe o inventário inteiro, e o erro só apareceria semanas depois, no
/// relatório final.
class TelaImportacao extends ConsumerStatefulWidget {
  final String inventarioId;

  const TelaImportacao({super.key, required this.inventarioId});

  @override
  ConsumerState<TelaImportacao> createState() => _TelaImportacaoState();
}

class _TelaImportacaoState extends ConsumerState<TelaImportacao> {
  int _passo = 0;
  bool _carregando = false;
  String? _erro;

  PlanilhaLida? _planilha;
  Mapeamento? _mapeamento;
  PreviaImportacao? _previa;
  final _edsExcluidos = <String>{};

  Future<void> _escolherArquivo() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final arquivo = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'txt'],
      );

      if (arquivo == null) {
        setState(() => _carregando = false);
        return;
      }

      // Ler os bytes pelo próprio `PlatformFile` mantém a leitura dentro do
      // que o seletor do sistema já autorizou, sem permissão de armazenamento.
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: arquivo.name,
        bytes: await arquivo.readAsBytes(),
      );
      final mapeamento = detectarMapeamento(planilha.linhas);

      setState(() {
        _planilha = planilha;
        _mapeamento = mapeamento;
        _carregando = false;
        _passo = 1;
      });
    } on PlanilhaInvalida catch (e) {
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não foi possível ler o arquivo: $e';
        _carregando = false;
      });
    }
  }

  void _confirmarMapeamento() {
    final planilha = _planilha!;
    final mapeamento = _mapeamento!;

    if (!mapeamento.valido) {
      setState(
        () => _erro =
            'Indique qual coluna contém o ${mapeamento.faltando.first.rotulo.toLowerCase()}.',
      );
      return;
    }

    setState(() {
      _previa = Importador.preparar(planilha, mapeamento);
      _erro = null;
      _passo = 2;
    });
  }

  Future<void> _importar() async {
    final previa = _previa!;
    setState(() => _carregando = true);

    try {
      final resultado = Importador.aplicar(
        repositorio: ref.read(patrimoniosProvider),
        inventarioId: widget.inventarioId,
        previa: previa,
        edsExcluidos: _edsExcluidos,
      );

      ref
          .read(inventariosProvider)
          .definirEdsExcluidos(widget.inventarioId, _edsExcluidos.toList());
      ref.read(revisaoProvider.notifier).mudou();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${resultado.inseridos} itens importados'
            '${resultado.preservados > 0 ? ' · ${resultado.preservados} já existiam e foram preservados' : ''}',
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _erro = 'Falha ao importar: $e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar planilha')),
      body: Column(
        children: [
          if (_erro != null)
            MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              content: Text(_erro!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _erro = null),
                  child: const Text('Entendi'),
                ),
              ],
            ),
          if (_carregando) const LinearProgressIndicator(),
          Expanded(
            child: switch (_passo) {
              0 => _PassoArquivo(
                aoEscolher: _carregando ? null : _escolherArquivo,
              ),
              1 => _PassoMapeamento(
                planilha: _planilha!,
                mapeamento: _mapeamento!,
                aoMudar: (m) => setState(() => _mapeamento = m),
                aoConfirmar: _confirmarMapeamento,
                aoVoltar: () => setState(() => _passo = 0),
              ),
              _ => _PassoElementos(
                previa: _previa!,
                excluidos: _edsExcluidos,
                aoAlternar: (ed, excluir) => setState(() {
                  if (excluir) {
                    _edsExcluidos.add(ed);
                  } else {
                    _edsExcluidos.remove(ed);
                  }
                }),
                aoImportar: _carregando ? null : _importar,
                aoVoltar: () => setState(() => _passo = 1),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _PassoArquivo extends StatelessWidget {
  final VoidCallback? aoEscolher;

  const _PassoArquivo({required this.aoEscolher});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(
          Icons.table_chart_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Escolha a planilha exportada do SUAP',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Aceita XLSX e CSV. As colunas são reconhecidas pelo nome, então a '
          'ordem não importa.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Planilhas .xls antigas precisam ser salvas como .xlsx antes.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: aoEscolher,
          icon: const Icon(Icons.folder_open),
          label: const Text('Escolher arquivo'),
        ),
      ],
    );
  }
}

class _PassoMapeamento extends StatelessWidget {
  final PlanilhaLida planilha;
  final Mapeamento mapeamento;
  final ValueChanged<Mapeamento> aoMudar;
  final VoidCallback aoConfirmar;
  final VoidCallback aoVoltar;

  const _PassoMapeamento({
    required this.planilha,
    required this.mapeamento,
    required this.aoMudar,
    required this.aoConfirmar,
    required this.aoVoltar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Confira as colunas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${planilha.nomeArquivo} · '
                '${planilha.totalLinhas - mapeamento.linhaCabecalho - 1} linhas de dados',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final campo in CampoImportacao.values)
                _SeletorCampo(
                  campo: campo,
                  colunaEscolhida: mapeamento.colunaDe(campo),
                  colunas: mapeamento.disponiveis,
                  aoEscolher: (coluna) =>
                      aoMudar(mapeamento.definir(campo, coluna)),
                ),
            ],
          ),
        ),
        _Rodape(
          aoVoltar: aoVoltar,
          aoAvancar: aoConfirmar,
          rotuloAvancar: 'Continuar',
        ),
      ],
    );
  }
}

class _SeletorCampo extends StatelessWidget {
  final CampoImportacao campo;
  final int? colunaEscolhida;
  final List<ColunaDetectada> colunas;
  final ValueChanged<int?> aoEscolher;

  const _SeletorCampo({
    required this.campo,
    required this.colunaEscolhida,
    required this.colunas,
    required this.aoEscolher,
  });

  @override
  Widget build(BuildContext context) {
    final escolhida = colunaEscolhida == null
        ? null
        : colunas.where((c) => c.indice == colunaEscolhida).firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  campo.rotulo,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (campo.obrigatorio)
                  Text(
                    ' *',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            DropdownButton<int?>(
              value: colunaEscolhida,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: Text(
                campo.obrigatorio ? 'Escolha a coluna' : 'Não importar',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Não importar'),
                ),
                for (final c in colunas)
                  DropdownMenuItem(
                    value: c.indice,
                    child: Text(c.cabecalho, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: aoEscolher,
            ),
            // A amostra é o que permite perceber um reconhecimento errado
            // antes de importar: o nome da coluna pode enganar, o conteúdo não.
            if (escolhida != null && escolhida.amostra.isNotEmpty)
              Text(
                'Exemplo: ${escolhida.amostra.take(3).join(' · ')}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _PassoElementos extends StatelessWidget {
  final PreviaImportacao previa;
  final Set<String> excluidos;
  final void Function(String ed, bool excluir) aoAlternar;
  final VoidCallback? aoImportar;
  final VoidCallback aoVoltar;

  const _PassoElementos({
    required this.previa,
    required this.excluidos,
    required this.aoAlternar,
    required this.aoImportar,
    required this.aoVoltar,
  });

  @override
  Widget build(BuildContext context) {
    final entrarao = previa.totalConsiderando(excluidos);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${previa.total} patrimônios encontrados',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (previa.semTombo > 0)
                        Text(
                          '${previa.semTombo} linhas sem tombo, descartadas',
                        ),
                      if (previa.tombosDuplicados.isNotEmpty)
                        Text(
                          '${previa.tombosDuplicados.length} tombos repetidos '
                          'no arquivo; cada um entra uma vez.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Elementos de despesa',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Desmarque o que não entra no inventário — material '
                'bibliográfico, por exemplo. Os itens continuam no aparelho, '
                'mas não aparecem como pendentes.',
              ),
              const SizedBox(height: 12),
              for (final entrada in previa.contagemPorEd.entries)
                CheckboxListTile(
                  value: !excluidos.contains(entrada.key),
                  onChanged: (incluir) =>
                      aoAlternar(entrada.key, !(incluir ?? true)),
                  title: Text(
                    entrada.key.isEmpty
                        ? 'Sem elemento de despesa'
                        : 'ED ${entrada.key}',
                  ),
                  subtitle: Text('${entrada.value} itens'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$entrarao entrarão no inventário',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        _Rodape(
          aoVoltar: aoVoltar,
          aoAvancar: aoImportar,
          rotuloAvancar: 'Importar',
        ),
      ],
    );
  }
}

class _Rodape extends StatelessWidget {
  final VoidCallback aoVoltar;
  final VoidCallback? aoAvancar;
  final String rotuloAvancar;

  const _Rodape({
    required this.aoVoltar,
    required this.aoAvancar,
    required this.rotuloAvancar,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            OutlinedButton(onPressed: aoVoltar, child: const Text('Voltar')),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: aoAvancar,
                child: Text(rotuloAvancar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
