import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../app/tema.dart';
import '../../data/repos/patrimonios.dart';
import 'estado_levantamento.dart';

/// Uma leitura da sessão, com o resultado destacado.
///
/// O resultado é dito por ícone, cor e texto: quem não distingue as cores, ou
/// usa leitor de tela, recebe a mesma informação.
class LinhaLeitura extends StatelessWidget {
  final LeituraRegistrada registro;

  /// Abre o item lido. Sem ele a linha é só informativa.
  final VoidCallback? aoTocar;

  const LinhaLeitura({super.key, required this.registro, this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final cores = CoresResultado.of(context);
    final tema = Theme.of(context);
    final p = registro.patrimonio;

    // A verificação pode ter sido desfeita na ficha do item depois da leitura:
    // o marcador verde diria o contrário do que está no banco.
    final desfeita = p != null && !p.verificado;
    final tom = desfeita ? cores.neutro : cores.daLeitura(registro.resultado);
    final icone = desfeita
        ? Icons.undo
        : CoresResultado.iconeDaLeitura(registro.resultado);

    final identificacao = p == null
        ? null
        : 'Cód. barras: ${p.codigoBarras ?? '—'} | Tombo: ${p.tombo}';
    final detalhe = p == null
        ? 'Não localizado neste inventário'
        : desfeita
        ? 'Verificação desfeita'
        : '${registro.resultado == ResultadoLeitura.jaVerificado ? 'Já verificado' : 'Verificado'}'
              '${p.verificadoPor == null ? '' : ' por ${p.verificadoPor}'}';

    final avisos = [
      if (registro.leitura.temDuplicados)
        '${registro.leitura.duplicados} itens com este código',
      if (p != null && p.ignorado)
        'Este item está fora do inventário (ED excluído)',
    ];

    final estiloDetalhe = tema.textTheme.bodySmall?.copyWith(color: tom.texto);

    return MergeSemantics(
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icone, color: tom.texto, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.descricao ?? 'Código ${registro.codigoLido}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    if (identificacao != null)
                      Text(identificacao, style: estiloDetalhe),
                    Text(detalhe, style: estiloDetalhe),
                    for (final aviso in avisos)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          aviso,
                          style: tema.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O que aparece atrás da linha enquanto ela desliza para a esquerda.
class FundoDesfazer extends StatelessWidget {
  const FundoDesfazer({super.key});

  @override
  Widget build(BuildContext context) {
    final tom = CoresResultado.of(context).naoLocalizado;

    return ColoredBox(
      color: tom.fundo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.undo, color: tom.texto, size: 22),
            const SizedBox(width: 8),
            Text(
              'Desfazer',
              style: TextStyle(color: tom.texto, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma [LinhaLeitura] que some ao deslizar da direita para a esquerda.
class LeituraDeslizavel extends StatelessWidget {
  final LeituraRegistrada registro;
  final VoidCallback aoDesfazer;
  final VoidCallback? aoTocar;

  const LeituraDeslizavel({
    super.key,
    required this.registro,
    required this.aoDesfazer,
    this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ObjectKey(registro),
      direction: DismissDirection.endToStart,
      background: const FundoDesfazer(),
      onDismissed: (_) => aoDesfazer(),
      child: LinhaLeitura(registro: registro, aoTocar: aoTocar),
    );
  }
}

/// O que o leitor de tela diz depois de uma leitura.
///
/// Os três resultados já se distinguem por som, vibração, ícone, cor e texto;
/// quem usa o TalkBack precisa ouvir o resultado também, sem ter de navegar
/// até o histórico a cada item.
String anuncioDaLeitura(LeituraRegistrada registro) {
  final p = registro.patrimonio;
  return switch (registro.resultado) {
    ResultadoLeitura.sucesso =>
      'Registrado. ${p?.descricao ?? ''}, tombo ${p?.tombo ?? registro.codigoLido}.',
    ResultadoLeitura.jaVerificado =>
      'Já verificado${p?.verificadoPor == null ? '' : ' por ${p!.verificadoPor}'}. '
          '${p?.descricao ?? ''}. Manter ou regravar?',
    ResultadoLeitura.naoLocalizado =>
      'Não localizado. Código ${registro.codigoLido}.',
  };
}

/// Anuncia o resultado de uma leitura, com prioridade: interrompe o que o
/// leitor de tela estiver dizendo, porque a leitura seguinte vem logo.
void anunciarLeitura(BuildContext context, LeituraRegistrada registro) {
  SemanticsService.sendAnnouncement(
    View.of(context),
    anuncioDaLeitura(registro),
    Directionality.of(context),
    assertiveness: Assertiveness.assertive,
  );
}
