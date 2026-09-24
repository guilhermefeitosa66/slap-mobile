import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/formato.dart';
import '../../data/banco.dart';
import '../../data/copia_seguranca.dart';
import '../../data/repos/inventarios.dart';
import '../../domain/valores.dart';

/// Exportar e restaurar a cópia de segurança, pelo seletor do sistema.

/// Gera a cópia fora da thread de interface e devolve o conteúdo do arquivo.
Future<Uint8List> gerarCopia(Banco banco, {String? inventarioId}) async {
  final pasta = await getTemporaryDirectory();
  final destino =
      '${pasta.path}/copia-${DateTime.now().microsecondsSinceEpoch}'
      '.${CopiaDeSeguranca.extensao}';

  final caminho = banco.caminho;
  if (caminho == null) {
    CopiaDeSeguranca.exportar(banco, destino, inventarioId: inventarioId);
  } else {
    // Segunda conexão, num isolate: com milhares de operações o VACUUM leva
    // alguns segundos, e a interface não pode parar.
    await Isolate.run(() {
      final outro = Banco.abrirSincrono(caminho);
      try {
        CopiaDeSeguranca.exportar(outro, destino, inventarioId: inventarioId);
      } finally {
        outro.fechar();
      }
    });
  }

  final arquivo = File(destino);
  try {
    return await arquivo.readAsBytes();
  } finally {
    await arquivo.delete();
  }
}

/// Traz a cópia para o banco, fora da thread de interface.
Future<ResultadoRestauracao> aplicarCopia(Banco banco, String arquivo) {
  final caminho = banco.caminho;
  if (caminho == null) {
    return Future.value(CopiaDeSeguranca.restaurar(banco, arquivo));
  }
  return Isolate.run(() {
    final outro = Banco.abrirSincrono(caminho);
    try {
      return CopiaDeSeguranca.restaurar(outro, arquivo);
    } finally {
      outro.fechar();
    }
  });
}

/// Exporta todos os inventários, ou só [inventario], e deixa a pessoa
/// escolher onde guardar.
Future<void> exportarCopia(
  BuildContext context,
  WidgetRef ref, {
  Inventario? inventario,
}) async {
  final mensageiro = ScaffoldMessenger.of(context);
  final fechar = _mostrarAndamento(context, 'Preparando a cópia…');

  final Uint8List bytes;
  try {
    bytes = await gerarCopia(
      ref.read(bancoProvider),
      inventarioId: inventario?.id,
    );
  } catch (e) {
    fechar();
    mensageiro.showSnackBar(
      SnackBar(content: Text('Não foi possível gerar a cópia: $e')),
    );
    return;
  } finally {
    fechar();
  }

  final nome = [
    'slap',
    if (inventario != null) _semAcentos(inventario.titulo),
    DateFormat('yyyyMMdd-HHmm').format(DateTime.now()),
  ].join('-');

  try {
    final salvo = await FilePicker.saveFile(
      fileName: '$nome.${CopiaDeSeguranca.extensao}',
      bytes: bytes,
      dialogTitle: 'Onde guardar a cópia',
    );
    if (salvo == null) return;
    mensageiro.showSnackBar(
      const SnackBar(
        content: Text(
          'Cópia guardada. Mantenha-a fora deste celular — num computador, '
          'no e-mail ou num drive.',
        ),
      ),
    );
  } catch (e) {
    mensageiro.showSnackBar(
      SnackBar(content: Text('Não foi possível guardar a cópia: $e')),
    );
  }
}

/// Escolhe uma cópia, mostra o que há nela e traz para este aparelho.
Future<void> restaurarCopia(BuildContext context, WidgetRef ref) async {
  final mensageiro = ScaffoldMessenger.of(context);
  final banco = ref.read(bancoProvider);

  final escolhido = await FilePicker.pickFile(
    dialogTitle: 'Escolha a cópia de segurança',
  );
  if (escolhido == null || !context.mounted) return;

  // O seletor entrega os bytes; a cópia precisa ser um arquivo para o
  // SQLite abrir.
  final pasta = await getTemporaryDirectory();
  final temporario = File(
    '${pasta.path}/restaurar-${DateTime.now().microsecondsSinceEpoch}.db',
  );
  await temporario.writeAsBytes(await escolhido.readAsBytes());

  try {
    final ResumoCopia resumo;
    try {
      resumo = CopiaDeSeguranca.ler(temporario.path, comparadoCom: banco);
    } on CopiaInvalida catch (e) {
      if (context.mounted) {
        await _avisar(context, 'Arquivo não aceito', e.mensagem);
      }
      return;
    }
    if (!context.mounted) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (contexto) => _ConfirmarRestauracao(resumo: resumo),
    );
    if (confirmou != true || !context.mounted) return;

    final fechar = _mostrarAndamento(context, 'Restaurando…');
    try {
      final resultado = await aplicarCopia(banco, temporario.path);
      fechar();
      ref.read(revisaoProvider.notifier).mudou();
      mensageiro.showSnackBar(
        SnackBar(
          content: Text(
            '${resultado.inventarios} '
            '${resultado.inventarios == 1 ? 'inventário restaurado' : 'inventários restaurados'}'
            '${resultado.inventariosNovos > 0 ? ', ${resultado.inventariosNovos} novo${resultado.inventariosNovos == 1 ? '' : 's'}' : ''}'
            ' · ${formatarInteiro(resultado.operacoes)} alterações trazidas',
          ),
        ),
      );
    } catch (e) {
      fechar();
      if (context.mounted) {
        await _avisar(
          context,
          'A cópia não foi restaurada',
          '$e\n\nNada foi alterado neste aparelho.',
        );
      }
    }
  } finally {
    if (temporario.existsSync()) await temporario.delete();
  }
}

class _ConfirmarRestauracao extends StatelessWidget {
  final ResumoCopia resumo;

  const _ConfirmarRestauracao({required this.resumo});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final origem = [
      if (resumo.autor != null && resumo.autor!.isNotEmpty)
        'de ${resumo.autor}',
      if (resumo.criadaEm != null) descreverMomento(resumo.criadaEm!),
    ].join(', ');

    return AlertDialog(
      title: const Text('Restaurar esta cópia?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (origem.isNotEmpty) ...[
              Text('Cópia $origem.'),
              const SizedBox(height: 12),
            ],
            for (final inv in resumo.inventarios)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${inv.nome} — ${inv.ano} '
                  '(${formatarInteiro(inv.itens)} itens'
                  '${inv.jaExiste ? ', já está neste aparelho' : ''})',
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Nada é apagado: o que a cópia tem e este aparelho não, entra; o '
              'resto fica como está. Este aparelho continua com a identidade '
              'dele, e o que ele fizer daqui em diante sai em nome dele.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Restaurar'),
        ),
      ],
    );
  }
}

/// Diálogo de andamento sem botão. Devolve a função que o fecha, segura
/// para chamar mais de uma vez.
VoidCallback _mostrarAndamento(BuildContext context, String texto) {
  final navegador = Navigator.of(context, rootNavigator: true);
  var aberto = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(texto)),
          ],
        ),
      ),
    ),
  );
  return () {
    if (!aberto) return;
    aberto = false;
    navegador.pop();
  };
}

Future<void> _avisar(BuildContext context, String titulo, String texto) {
  return showDialog<void>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(contexto),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
}

String _semAcentos(String texto) => formaComparavel(
  texto,
).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
