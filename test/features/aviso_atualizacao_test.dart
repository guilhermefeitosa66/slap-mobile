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
    expect(find.text('Baixar nova versão'), findsOneWidget);
  });

  testWidgets('a faixa passa na auditoria de acessibilidade', (tester) async {
    // O laranja é o tom de aviso do aplicativo, e o botão inverte fundo e
    // texto dele. Contraste e alvo de toque conferidos com a faixa na tela.
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('em dia, o rodapé confirma discretamente', (tester) async {
    await abrir(tester, fixo('{"tag_name": "v$versaoApp"}'));

    expect(find.text('Versão $versaoApp'), findsOneWidget);
    expect(find.text('atualizado'), findsOneWidget);
  });

  testWidgets('sem conferir, o rodapé não afirma que está em dia', (
    tester,
  ) async {
    // Dizer "atualizado" sem ter perguntado é pior que não dizer nada.
    await abrir(tester, VerificadorAtualizacao(buscar: (_) async => null));

    expect(find.text('Versão $versaoApp'), findsOneWidget);
    expect(find.text('atualizado'), findsNothing);
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

  testWidgets('dispensada, some enquanto o aplicativo está aberto', (
    tester,
  ) async {
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(find.textContaining('disponível'), findsNothing);
  });

  testWidgets('fechar e abrir o aplicativo volta a avisar', (tester) async {
    // A dispensa não é gravada: quem está no meio de um levantamento manda
    // calar e segue, mas quem abre o aplicativo de novo é lembrado enquanto
    // não instalar.
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    // Outra abertura: outro container de provedores, como no aplicativo.
    await abrir(tester, fixo('{"tag_name": "v9.9.9"}'));

    expect(find.textContaining('Versão 9.9.9 disponível'), findsOneWidget);
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
