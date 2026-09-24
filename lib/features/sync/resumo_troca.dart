import '../../core/formato.dart';
import 'cliente.dart';

/// O que dizer ao fim de uma troca de dados.
///
/// A barra de andamento some rápido quando há pouca coisa a trocar, e quem
/// tocou fica sem saber se deu certo. O aviso de conclusão é a confirmação
/// que falta — e é onde os números aparecem na unidade que interessa a quem
/// conduz o inventário.
class ResumoTroca {
  final String titulo;

  /// Uma frase por linha, na ordem em que se lê.
  final List<String> linhas;

  /// Falso quando nada foi trocado — nem por novidade, nem por falha.
  final bool houveTroca;

  /// Conflitos que a troca deixou para alguém conferir.
  final int conflitos;

  const ResumoTroca({
    required this.titulo,
    required this.linhas,
    required this.houveTroca,
    this.conflitos = 0,
  });
}

/// Uma troca que falhou, para o resumo de "Trocar com todos".
class FalhaNaTroca {
  final String rotulo;
  final String mensagem;

  const FalhaNaTroca(this.rotulo, this.mensagem);
}

/// Resumo da troca com um aparelho.
ResumoTroca resumirTroca(ResultadoSync r) {
  final quem = r.par.rotulo;

  if (!r.houveTroca) {
    return ResumoTroca(
      titulo: 'Já estava tudo sincronizado',
      linhas: [
        'Nem você nem $quem tinham novidade. Nada precisou ser trocado.',
      ],
      houveTroca: false,
    );
  }

  return ResumoTroca(
    titulo: 'Dados trocados com $quem',
    linhas: [
      _oQueVeio(r, quem),
      _oQueFoi(r, quem),
      if (r.conflitos > 0) _conflitos(r.conflitos),
    ],
    houveTroca: true,
    conflitos: r.conflitos,
  );
}

/// Resumo de "Trocar com todos": uma linha por aparelho, na ordem em que
/// foram percorridos.
///
/// Por aparelho, e não só o total: numa comissão, saber que a troca com um
/// deles falhou vale mais que o número somado dos outros.
ResumoTroca resumirTrocas(
  List<ResultadoSync> resultados,
  List<FalhaNaTroca> falhas,
) {
  final total = resultados.length + falhas.length;
  final conflitos = resultados.fold(0, (soma, r) => soma + r.conflitos);
  final trocou = resultados.any((r) => r.houveTroca);

  return ResumoTroca(
    titulo: falhas.isEmpty
        ? 'Troca concluída com ${_aparelhos(total)}'
        : 'Troca concluída com ressalvas',
    linhas: [
      for (final r in resultados) '${r.par.rotulo}: ${_resumoCurto(r)}',
      for (final f in falhas) '${f.rotulo}: ${f.mensagem}',
      if (conflitos > 0) _conflitos(conflitos),
    ],
    houveTroca: trocou,
    conflitos: conflitos,
  );
}

/// Aviso de uma troca que não aconteceu.
///
/// A mensagem vem pronta de quem a recusou — relógio fora de sincronia e
/// identidade duplicada explicam o caso inteiro, e reescrevê-las aqui só
/// perderia informação.
ResumoTroca resumirFalha(String rotulo, String mensagem) => ResumoTroca(
  titulo: 'Não foi possível trocar com $rotulo',
  linhas: [mensagem],
  houveTroca: false,
);

String _oQueVeio(ResultadoSync r, String quem) {
  if (r.recebidas == 0) return 'Nada novo veio de $quem.';
  if (r.itensAtualizados > 0) {
    return '${_itens(r.itensAtualizados)} ${r.itensAtualizados == 1 ? 'veio' : 'vieram'} '
        'de $quem.';
  }
  return '${_alteracoes(r.recebidas)} '
      '${r.recebidas == 1 ? 'veio' : 'vieram'} de $quem.';
}

String _oQueFoi(ResultadoSync r, String quem) => r.enviadas == 0
    ? '$quem já tinha tudo o que você levantou.'
    : '${_alteracoes(r.enviadas)} '
          '${r.enviadas == 1 ? 'sua foi' : 'suas foram'} para $quem.';

/// A linha curta de cada aparelho no resumo de "Trocar com todos".
String _resumoCurto(ResultadoSync r) {
  if (!r.houveTroca) return 'já estava sincronizado';
  final partes = [
    // Na linha curta, "itens" basta: o que os qualifica é o "recebidos" ao
    // lado, e "itens atualizados recebidos" empilha três palavras sem ganho.
    if (r.itensAtualizados > 0)
      '${_itensCurto(r.itensAtualizados)} ${r.itensAtualizados == 1 ? 'recebido' : 'recebidos'}'
    else if (r.recebidas > 0)
      '${_alteracoes(r.recebidas)} ${r.recebidas == 1 ? 'recebida' : 'recebidas'}',
    if (r.enviadas > 0)
      '${_alteracoes(r.enviadas)} ${r.enviadas == 1 ? 'enviada' : 'enviadas'}',
  ];
  return partes.join(', ');
}

String _conflitos(int quantos) => quantos == 1
    ? '1 conflito ficou para conferir.'
    : '${formatarInteiro(quantos)} conflitos ficaram para conferir.';

String _itens(int n) =>
    n == 1 ? '1 item atualizado' : '${formatarInteiro(n)} itens atualizados';

String _itensCurto(int n) => n == 1 ? '1 item' : '${formatarInteiro(n)} itens';

String _alteracoes(int n) =>
    n == 1 ? '1 alteração' : '${formatarInteiro(n)} alterações';

String _aparelhos(int n) =>
    n == 1 ? '1 aparelho' : '${formatarInteiro(n)} aparelhos';
