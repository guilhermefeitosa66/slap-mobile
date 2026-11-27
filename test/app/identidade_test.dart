import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/data/banco.dart';

/// Quem usa o aparelho: nome e, se houver, matrícula.
void main() {
  test('matrícula em branco fica ausente, sem "Nome · " nem "Nome ()"', () {
    final banco = Banco.emMemoria();
    addTearDown(banco.fechar);
    final c = ProviderContainer(
      overrides: [bancoProvider.overrideWithValue(banco)],
    );
    addTearDown(c.dispose);

    c
        .read(identidadeProvider.notifier)
        .definir(nome: ' Marta Lima ', matricula: '  ');
    final agora = c.read(identidadeProvider);
    expect(agora.nome, 'Marta Lima');
    expect(agora.matricula, isNull);

    c
        .read(identidadeProvider.notifier)
        .definir(nome: 'Marta Lima', matricula: ' 123 ');
    expect(c.read(identidadeProvider).matricula, '123');
  });
}
