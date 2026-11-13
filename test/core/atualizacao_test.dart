import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/atualizacao.dart';

/// A verificação de versão nova.
///
/// Ela roda sozinha a cada abertura, sem ninguém pedir, e por isso o que mais
/// importa aqui não é o caminho feliz: é que nenhuma resposta estranha da rede
/// vire exceção na cara de quem só quer começar a levantar.
void main() {
  VerificadorAtualizacao com(String? corpo) =>
      VerificadorAtualizacao(buscar: (_) async => corpo);

  test('a versão do código é a do pubspec', () {
    // A constante existe para não precisar de um plugin só para ler o
    // pubspec em tempo de execução. Este teste é o que a mantém honesta.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declarada = RegExp(
      r'^version:\s*([0-9]+(?:\.[0-9]+)*)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);

    expect(versaoApp, declarada);
  });

  group('comparação de versões', () {
    test('mais nova em qualquer casa', () {
      expect(versaoEhMaisNova('1.1.0', '1.0.0'), isTrue);
      expect(versaoEhMaisNova('2.0.0', '1.9.9'), isTrue);
      expect(versaoEhMaisNova('1.0.1', '1.0.0'), isTrue);
    });

    test('igual não é mais nova, com ou sem casas a mais', () {
      expect(versaoEhMaisNova('1.1.0', '1.1.0'), isFalse);
      expect(versaoEhMaisNova('1.2', '1.2.0'), isFalse);
      expect(versaoEhMaisNova('1.2.0', '1.2'), isFalse);
    });

    test('mais velha nunca avisa', () {
      expect(versaoEhMaisNova('1.0.0', '1.1.0'), isFalse);
      expect(versaoEhMaisNova('1.9.0', '1.10.0'), isFalse);
    });

    test('compara número, não texto', () {
      // O erro clássico: por texto, "1.10.0" vem antes de "1.9.0".
      expect(versaoEhMaisNova('1.10.0', '1.9.0'), isTrue);
      expect(versaoEhMaisNova('1.9.0', '1.10.0'), isFalse);
    });

    test('o "v" da tag e o código de build não atrapalham', () {
      expect(versaoEhMaisNova('v1.2.0', '1.1.0'), isTrue);
      expect(versaoEhMaisNova('1.2.0+7', '1.1.0+2'), isTrue);
      expect(versaoEhMaisNova('SLAP 1.2', '1.1.0'), isTrue);
    });

    test('sem número não dá para comparar, e não se avisa', () {
      expect(versaoEhMaisNova('', '1.0.0'), isFalse);
      expect(versaoEhMaisNova('mais-nova', '1.0.0'), isFalse);
      expect(versaoEhMaisNova('1.0.0', 'sei lá'), isFalse);
    });
  });

  group('verificação', () {
    test('versão mais nova é anunciada sem o "v" da tag', () async {
      final r = await com(
        '{"tag_name": "v1.4.0"}',
      ).verificar(versaoAtual: '1.1.0');

      expect(r, isNotNull);
      expect(r!.versao, '1.4.0');
      expect(r.endereco, enderecoComoAtualizar);
    });

    test('em dia não avisa nada', () async {
      final r = await com(
        '{"tag_name": "v1.1.0"}',
      ).verificar(versaoAtual: '1.1.0');

      expect(r, isNull);
    });

    test('release mais velha que a instalada não avisa', () async {
      final r = await com(
        '{"tag_name": "v1.0.0"}',
      ).verificar(versaoAtual: '1.1.0');

      expect(r, isNull);
    });

    test('sem tag, cai no nome da release', () async {
      final r = await com(
        '{"name": "SLAP 1.5.0"}',
      ).verificar(versaoAtual: '1.1.0');

      expect(r?.versao, '1.5.0');
    });

    test('resposta malformada não derruba nada', () async {
      for (final corpo in [
        'não é json',
        '[]',
        '{}',
        '{"tag_name": null}',
        '{"tag_name": ""}',
        '{"tag_name": "sem número"}',
      ]) {
        expect(
          await com(corpo).verificar(versaoAtual: '1.1.0'),
          isNull,
          reason: 'corpo: $corpo',
        );
      }
    });

    test('sem rede não avisa, e não lança', () async {
      final semRede = VerificadorAtualizacao(
        buscar: (_) => Future.error(const SocketException('sem rede')),
      );

      expect(await semRede.verificar(versaoAtual: '1.1.0'), isNull);
    });

    test('resposta que nunca chega não fica pendurada no aplicativo', () async {
      // A falha é da busca, que tem o seu próprio tempo limite; aqui o que se
      // confere é que o erro dela vira "nada a avisar".
      final travado = VerificadorAtualizacao(
        buscar: (_) => Future.error(TimeoutException('demorou')),
      );

      expect(await travado.verificar(versaoAtual: '1.1.0'), isNull);
    });
  });

  group('origem da instalação', () {
    test('instalado pela Play, pergunta à Play', () {
      expect(
        origemPeloInstalador('com.android.vending'),
        OrigemInstalacao.googlePlay,
      );
    });

    test('APK instalado à mão ou por outra loja, pergunta ao GitHub', () {
      for (final instalador in [
        null,
        '',
        'com.google.android.packageinstaller',
        'com.android.shell',
      ]) {
        expect(
          origemPeloInstalador(instalador),
          OrigemInstalacao.foraDasLojas,
          reason: 'instalador: $instalador',
        );
      }
    });
  });

  group('na Google Play', () {
    VerificadorAtualizacao play(Future<bool?> Function() consultar) =>
        VerificadorAtualizacao(
          origem: () async => OrigemInstalacao.googlePlay,
          consultarPlay: consultar,
          buscar: (_) async => fail('na Play não se pergunta ao GitHub'),
        );

    test('com atualização, leva à ficha da Play', () async {
      final r = await play(() async => true).verificar(versaoAtual: '1.1.0');

      expect(r, isNotNull);
      expect(r!.versao, isNull, reason: 'a Play não diz o número');
      expect(r.origem, OrigemInstalacao.googlePlay);
      expect(r.endereco, enderecoPlay);
    });

    test('sem atualização, está em dia', () async {
      final c = await play(() async => false).consultar(versaoAtual: '1.1.0');

      expect(c, isNotNull);
      expect(c!.nova, isNull);
    });

    test('a Play sem resposta, ou com erro, não afirma nada', () async {
      expect(await play(() async => null).consultar(), isNull);
      expect(
        await play(() => Future.error(Exception('fora da Play'))).consultar(),
        isNull,
      );
    });
  });

  group('na App Store', () {
    VerificadorAtualizacao appStore(String? corpo) => VerificadorAtualizacao(
      origem: () async => OrigemInstalacao.appStore,
      buscar: (endereco) async {
        expect(endereco.toString(), enderecoLookupApple);
        return corpo;
      },
    );

    test('versão mais nova na loja leva à página dela', () async {
      final r = await appStore(
        '{"resultCount": 1, "results": [{"version": "1.4.0", '
        '"trackViewUrl": "https://apps.apple.com/br/app/slap/id1"}]}',
      ).verificar(versaoAtual: '1.3.3');

      expect(r!.versao, '1.4.0');
      expect(r.origem, OrigemInstalacao.appStore);
      expect(r.endereco, 'https://apps.apple.com/br/app/slap/id1');
    });

    test('sem o endereço na resposta, usa o da página do app', () async {
      final r = await appStore(
        '{"results": [{"version": "9.0.0"}]}',
      ).verificar(versaoAtual: '1.3.3');

      expect(r!.endereco, enderecoAppStore);
    });

    test('mesma versão da loja está em dia', () async {
      final c = await appStore(
        '{"results": [{"version": "1.3.3"}]}',
      ).consultar(versaoAtual: '1.3.3');

      expect(c, isNotNull);
      expect(c!.nova, isNull);
    });

    test('resposta vazia ou malformada não afirma nada', () async {
      for (final corpo in [
        null,
        'não é json',
        '{"resultCount": 0, "results": []}',
        '{"results": [{"version": "sem número"}]}',
        '{"results": "x"}',
      ]) {
        expect(
          await appStore(corpo).consultar(versaoAtual: '1.3.3'),
          isNull,
          reason: 'corpo: $corpo',
        );
      }
    });
  });
}
