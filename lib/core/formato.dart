import 'package:intl/intl.dart';

/// Números como se escrevem em português: `1.204` e `60,2`.
///
/// Os relatórios e a interface são lidos por comissões acostumadas ao
/// formato brasileiro; `60.2%` parece erro de digitação a quem lê.
final _inteiro = NumberFormat.decimalPattern('pt_BR');
final _umaCasa = NumberFormat('0.0', 'pt_BR');

String formatarInteiro(int n) => _inteiro.format(n);

/// Percentual com uma casa decimal, sem o símbolo.
String formatarPercentual(double p) => _umaCasa.format(p);

/// Duração por extenso e arredondada, para mensagens: `12 min`, `2 h 5 min`,
/// `3 dias`.
String descreverDuracao(Duration d) {
  final minutos = d.inMinutes.abs();
  if (minutos < 1) return 'menos de 1 min';
  if (minutos < 60) return '$minutos min';
  final horas = d.inHours.abs();
  if (horas < 48) {
    final resto = minutos % 60;
    return resto == 0 ? '$horas h' : '$horas h $resto min';
  }
  return '${d.inDays.abs()} dias';
}
