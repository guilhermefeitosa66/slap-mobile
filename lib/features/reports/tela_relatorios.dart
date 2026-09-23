import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import 'relatorios.dart';

/// Exportação dos resultados.
///
/// Qualquer aparelho sincronizado produz os mesmos relatórios: como toda
/// réplica tem o log completo de operações, não é preciso voltar ao aparelho
/// que criou o inventário.
class TelaRelatorios extends ConsumerStatefulWidget {
  final String inventarioId;

  const TelaRelatorios({super.key, required this.inventarioId});

  @override
  ConsumerState<TelaRelatorios> createState() => _TelaRelatoriosState();
}

class _TelaRelatoriosState extends ConsumerState<TelaRelatorios> {
  bool _gerando = false;

  Future<void> _exportar(TipoRelatorio tipo, {required bool xlsx}) async {
    final inventario = ref.read(inventarioProvider(widget.inventarioId));
    if (inventario == null) return;

    setState(() => _gerando = true);

    try {
      final relatorio = GeradorRelatorios.gerar(
        tipo: tipo,
        inventario: inventario,
        patrimonios: ref.read(patrimoniosProvider).todos(widget.inventarioId),
      );

      if (relatorio.vazio) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nenhum item em "${tipo.titulo}".')),
        );
        return;
      }

      final bytes = xlsx
          ? GeradorRelatorios.paraXlsx(relatorio)
          : GeradorRelatorios.paraCsv(relatorio);

      // O arquivo vai para o diretório temporário e é entregue ao seletor do
      // sistema. Assim o usuário escolhe o destino — e-mail, Drive, pasta —
      // sem que o aplicativo precise de permissão de armazenamento.
      final diretorio = await getTemporaryDirectory();
      final caminho =
          '${diretorio.path}/${relatorio.nomeArquivo}.${xlsx ? 'xlsx' : 'csv'}';
      await File(caminho).writeAsBytes(bytes);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(caminho)],
          subject: '${relatorio.tipo.titulo} — ${inventario.titulo}',
          text: '${relatorio.total} itens.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao gerar o relatório: $e')));
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progresso = ref.watch(progressoProvider(widget.inventarioId));

    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: Column(
        children: [
          if (_gerando) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (progresso.pendentes > 0)
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Ainda há ${progresso.pendentes} patrimônios não '
                        'verificados. Se o inventário não terminou, eles vão '
                        'aparecer como não localizados.',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final tipo in TipoRelatorio.values)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tipo.titulo,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(tipo.descricao),
                          const SizedBox(height: 4),
                          Text(
                            _quantidade(tipo, progresso),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _gerando
                                      ? null
                                      : () => _exportar(tipo, xlsx: true),
                                  icon: const Icon(Icons.table_chart, size: 18),
                                  label: const Text('XLSX'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _gerando
                                      ? null
                                      : () => _exportar(tipo, xlsx: false),
                                  icon: const Icon(Icons.description, size: 18),
                                  label: const Text('CSV'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _quantidade(TipoRelatorio tipo, progresso) => switch (tipo) {
    TipoRelatorio.ok => '${progresso.ok} itens',
    TipoRelatorio.divergencias => '${progresso.divergentes} itens',
    TipoRelatorio.naoLocalizados => '${progresso.naoLocalizados} itens',
    TipoRelatorio.completo => '${progresso.total} itens',
  };
}
