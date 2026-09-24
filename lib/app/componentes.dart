import 'package:flutter/material.dart';

import '../core/andamento.dart';
import 'tema.dart';

/// Peças visuais repetidas entre as telas, na forma do design.

/// O motivo do código de barras: cinco barras, a quarta mais curta.
///
/// É a marca do aplicativo — aparece na abertura, no botão de levantar e no
/// ícone. Desenhado em vez de vir de uma fonte de ícones para ser o mesmo
/// traço em todo lugar.
class IconeCodigoBarras extends StatelessWidget {
  final double tamanho;
  final Color? cor;

  const IconeCodigoBarras({super.key, this.tamanho = 24, this.cor});

  @override
  Widget build(BuildContext context) {
    final corFinal =
        cor ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: tamanho,
        child: CustomPaint(painter: _PintorCodigoBarras(corFinal)),
      ),
    );
  }
}

class _PintorCodigoBarras extends CustomPainter {
  final Color cor;

  _PintorCodigoBarras(this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    // Mesma geometria do SVG do design, numa grade de 24.
    final escala = size.width / 24;
    final pincel = Paint()
      ..color = cor
      ..strokeWidth = 2 * escala
      ..strokeCap = StrokeCap.round;

    const barras = [
      (3.0, 19.0),
      (7.0, 19.0),
      (11.0, 19.0),
      (15.0, 15.0),
      (19.0, 19.0),
    ];
    for (final (x, fim) in barras) {
      canvas.drawLine(
        Offset(x * escala, 5 * escala),
        Offset(x * escala, fim * escala),
        pincel,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorCodigoBarras antigo) => antigo.cor != cor;
}

/// Ícone dentro de um quadrado arredondado no tom do resultado.
class IconeEmTom extends StatelessWidget {
  final IconData icone;
  final TomResultado tom;
  final double tamanho;

  const IconeEmTom({
    super.key,
    required this.icone,
    required this.tom,
    this.tamanho = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(tamanho * 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(icone, color: tom.texto, size: tamanho * 0.52),
    );
  }
}

/// Barra de progresso na espessura do design, verde quando concluída.
class BarraProgresso extends StatelessWidget {
  /// De 0 a 1.
  final double valor;
  final double espessura;

  const BarraProgresso({super.key, required this.valor, this.espessura = 8});

  @override
  Widget build(BuildContext context) {
    final apoio = CoresApoio.of(context);
    final concluido = valor >= 1;

    return LinearProgressIndicator(
      value: valor.clamp(0, 1),
      semanticsLabel: 'Progresso',
      semanticsValue:
          '${(valor.clamp(0, 1) * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
      minHeight: espessura,
      borderRadius: BorderRadius.circular(espessura / 2),
      backgroundColor: apoio.trilho,
      color: concluido
          ? apoio.concluido
          : Theme.of(context).colorScheme.primary,
    );
  }
}

/// A barra das esperas longas: importação, entrada por rede e sincronização.
///
/// A mesma peça nos três lugares, pela mesma razão: quem está esperando quer
/// saber o que está acontecendo e quanto falta. Sem contagem para mostrar, a
/// barra fica indeterminada em vez de fingir progresso.
///
/// O anúncio para leitor de tela fica na etapa, que muda poucas vezes; a
/// contagem, que muda o tempo todo, vai no valor da barra — assim o avanço é
/// consultável sem inundar de mensagens quem usa TalkBack.
class BarraAndamento extends StatelessWidget {
  final Andamento andamento;

  /// Centraliza o texto, para quando a barra é o centro da tela e não uma
  /// faixa no alto dela.
  final bool centralizado;

  final EdgeInsetsGeometry padding;

  const BarraAndamento({
    super.key,
    required this.andamento,
    this.centralizado = false,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
  });

  @override
  Widget build(BuildContext context) {
    final apoio = CoresApoio.of(context);
    final contagem = andamento.contagem;
    final fracao = andamento.fracao;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: fracao,
          semanticsLabel: andamento.etapa,
          semanticsValue: fracao == null
              ? null
              : '${(fracao * 100).round()}%'
                    '${contagem == null ? '' : ' · $contagem'}',
        ),
        Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: centralizado
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  andamento.etapa,
                  textAlign: centralizado ? TextAlign.center : null,
                ),
              ),
              if (contagem != null)
                ExcludeSemantics(
                  child: Text(
                    contagem,
                    textAlign: centralizado ? TextAlign.center : null,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: apoio.apagado),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cartão com várias linhas separadas por divisória recuada, como os grupos
/// e as ações do painel.
class CartaoAgrupado extends StatelessWidget {
  final List<Widget> linhas;

  const CartaoAgrupado({super.key, required this.linhas});

  @override
  Widget build(BuildContext context) {
    final apoio = CoresApoio.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < linhas.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: apoio.trilho,
                ),
              linhas[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Seta de navegação no fim de uma linha. Não carrega informação, por isso
/// fica apagada e fora da leitura de tela.
class SetaNavegacao extends StatelessWidget {
  final Color? cor;

  const SetaNavegacao({super.key, this.cor});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Icon(
        Icons.chevron_right,
        color: cor ?? CoresApoio.of(context).apagado,
      ),
    );
  }
}
