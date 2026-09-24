import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/atualizacao.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';

import '../apoio/app_de_teste.dart';

/// A faixa de versão nova na lista de inventários.
///
/// O que se confere aqui é sobretudo o que ela **não** faz: não aparece sem
/// motivo, não volta depois de dispensada e não atrapalha a abertura quando a
/// consulta falha.
void main() {
  late Banco banco;

  setUp(() {
    banco = Banco.emMemoria();
    banco.gravarConfig(Config.usuarioNome, 'Ana');
  });

  tearDown(() => banco.fechar);

  /// Verificador que devolve sempre a mesma resposta, sem tocar na rede.
  VerificadorAtualizacao fixo(String? corpo) =>
      VerificadorAtualizacao(buscar: (_) async => corpo);

  Future<void> abrir(WidgetTester tester, VerificadorAtualizacao v) async {
    await montar(tester, const TelaInventarios(), banco: banco, atualizacao: v);
    // A consulta só começa depois do primeiro quadro, de propósito.
    await tester.pumpAndSettle();
  }

  testWidgets('versão nova aparece, com a instalada ao lado', (tester) async {
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));

    expect(find.textContaining('Versão 9.9.9 disponível'), findsOneWidget);
    expect(find.textContaining('Você está na $versaoApp'), findsOneWidget);
    expect(find.text('Ver como'), findsOneWidget);
  });

  testWidgets('em dia não mostra faixa nenhuma', (tester) async {
    await abrir(tester, fixo('{"tag_name": "v$versaoApp"}'));

    expect(find.textContaining('disponível'), findsNothing);
  });

  testWidgets('falha na consulta não deixa rastro na tela', (tester) async {
    // Sem rede é o caso comum em campo: a tela abre igual.
    await abrir(tester, VerificadorAtualizacao(buscar: (_) async => null));

    expect(find.textContaining('disponível'), findsNothing);
    expect(find.text('Inventários'), findsOneWidget);
  });

  testWidgets('dispensada, não volta na abertura seguinte', (tester) async {
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(find.textContaining('disponível'), findsNothing);
    expect(banco.lerConfig(Config.atualizacaoDispensada), '9.9.9');

    // De novo, como numa abertura seguinte.
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));
    expect(find.textContaining('disponível'), findsNothing);
  });

  testWidgets('dispensar uma versão não silencia a seguinte', (tester) async {
    banco.gravarConfig(Config.atualizacaoDispensada, '9.9.9');

    await abrir(tester, fixo('{"tag_name": "v9.9.10"}'));

    expect(find.textContaining('Versão 9.9.10 disponível'), findsOneWidget);
  });

  testWidgets('com a verificação desligada, nem se pergunta', (tester) async {
    banco.gravarConfig(Config.verificarAtualizacao, '0');
    var perguntou = false;

    await abrir(
      tester,
      VerificadorAtualizacao(
        buscar: (_) async {
          perguntou = true;
          return '{"tag_name": "v9.9.9"}';
        },
      ),
    );

    expect(perguntou, isFalse, reason: 'nada sai do aparelho');
    expect(find.textContaining('disponível'), findsNothing);
  });
}
