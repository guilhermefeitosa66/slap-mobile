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

final _hora = DateFormat('HH:mm');
final _diaMes = DateFormat('dd/MM');

/// Um momento dito em relação a hoje: `hoje às 09:10`, `ontem às 16:05`,
/// `em 12/09 às 16:05`.
String descreverMomento(DateTime momento, {DateTime? agora}) {
  final hoje = _dia(agora ?? DateTime.now());
  final dia = _dia(momento);
  final hora = _hora.format(momento);
  if (dia == hoje) return 'hoje às $hora';
  if (dia == hoje.subtract(const Duration(days: 1))) return 'ontem às $hora';
  return 'em ${_diaMes.format(momento)} às $hora';
}

/// Forma curta de "desde quando vale": `desde 14:32`, `desde ontem, 16:05`,
/// `desde 12/09`.
String descreverDesde(DateTime momento, {DateTime? agora}) {
  final hoje = _dia(agora ?? DateTime.now());
  final dia = _dia(momento);
  if (dia == hoje) return 'desde ${_hora.format(momento)}';
  if (dia == hoje.subtract(const Duration(days: 1))) {
    return 'desde ontem, ${_hora.format(momento)}';
  }
  return 'desde ${_diaMes.format(momento)}';
}

DateTime _dia(DateTime t) => DateTime(t.year, t.month, t.day);
