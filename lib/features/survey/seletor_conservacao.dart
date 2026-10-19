import 'package:flutter/material.dart';

import '../../domain/valores.dart';

/// Escolha do estado de conservação, nos valores do SUAP.
///
/// Cinco estados e "manter o do SUAP" não cabem lado a lado num celular, por
/// isso são chips que quebram linha, em vez do botão segmentado dos outros
/// campos. `null` é "manter o do SUAP": a leitura confirma o estado que o
/// cadastro já tem, como o responsável em branco.
///
/// Um valor do vocabulário antigo (`regular`, `ruim`) aparece como chip
/// marcado enquanto estiver escolhido, para a pessoa ver o que o item tem e
/// trocar — mas não se escolhe de novo depois de trocado.
class SeletorConservacao extends StatelessWidget {
  final EstadoConservacao? valor;
  final ValueChanged<EstadoConservacao?> aoEscolher;

  /// Texto do chip de "manter", que diz o estado do SUAP quando há um só item
  /// em jogo (o detalhe do item) e fica genérico na configuração da sala.
  final String rotuloManter;

  const SeletorConservacao({
    super.key,
    required this.valor,
    required this.aoEscolher,
    this.rotuloManter = 'Manter o do SUAP',
  });

  @override
  Widget build(BuildContext context) {
    final opcoes = [
      ...EstadoConservacao.selecionaveis,
      if (valor?.legado ?? false) valor!,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: Text(rotuloManter),
          selected: valor == null,
          onSelected: (_) => aoEscolher(null),
        ),
        for (final e in opcoes)
          ChoiceChip(
            label: Text(e.rotulo),
            selected: valor == e,
            onSelected: (_) => aoEscolher(e),
          ),
      ],
    );
  }
}
