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

  const LinhaLeitura({super.key, required this.registro});

  @override
  Widget build(BuildContext context) {
    final tom = CoresResultado.of(context).daLeitura(registro.resultado);
    final icone = CoresResultado.iconeDaLeitura(registro.resultado);
    final rotulo = CoresResultado.rotuloDaLeitura(registro.resultado);
    final tema = Theme.of(context);
    final p = registro.patrimonio;

    final detalhe = p == null
        ? 'Não localizado neste inventário'
        : 'Tombo ${p.tombo} · $rotulo'
              '${p.verificadoPor == null ? '' : ' por ${p.verificadoPor}'}';

    final avisos = [
      if (registro.leitura.achadoNoOutroCampo)
        'Encontrado no outro campo — cadastro inconsistente',
      if (registro.leitura.temDuplicados)
        '${registro.leitura.duplicados} itens com este código',
      if (p != null && p.ignorado)
        'Este item está fora do inventário (ED excluído)',
    ];

    return MergeSemantics(
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
                  Text(
                    detalhe,
                    style: tema.textTheme.bodySmall?.copyWith(color: tom.texto),
                  ),
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
