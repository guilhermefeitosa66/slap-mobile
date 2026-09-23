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
