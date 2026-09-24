import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';

import '../apoio/rede_simulada.dart';

/// O link de convite: o que ele carrega, o que ele **não** carrega e de
/// quantos formatos de endereço ele é lido.
void main() {
  late Aparelho a;

  setUp(() => a = Aparelho('Ana'));
  tearDown(() => a.fechar());

  ConviteLink conviteDeExemplo() => ConviteLink.de(
    a.inventarios.criar(nome: 'Campus Picos — Biblioteca', ano: 2026),
    dispositivo: a.dispositivoId,
  );

  group('link de convite', () {
    test('ida e volta preserva o inventário, o nome, o ano e o aparelho', () {
      final convite = conviteDeExemplo();
      final lido = ConviteLink.decodificar(convite.codificar());

      expect(lido, isNotNull);
      expect(lido!.inventarioId, convite.inventarioId);
      expect(lido.nome, 'Campus Picos — Biblioteca');
      expect(lido.ano, 2026);
      expect(lido.dispositivoOrigem, a.dispositivoId);
    });

    test('o link não carrega a chave de sincronização', () {
      // É a decisão de projeto da issue #55: um link encaminhado a quem não
      // devia não dá acesso a nada. A chave só é entregue depois do aceite.
      final inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
      final link = ConviteLink.de(
        inventario,
        dispositivo: a.dispositivoId,
      ).codificar();

      expect(link.contains(inventario.chaveSync), isFalse);
      expect(link.contains('k='), isFalse);
      expect(Uri.parse(link).fragment.contains('chave'), isFalse);
    });

    test('os dados vão no fragmento, que nunca chega ao servidor', () {
      final uri = Uri.parse(conviteDeExemplo().codificar());

      expect(uri.host, hostSite);
      expect(uri.path, caminhoEntrar);
      expect(uri.query, isEmpty);
      expect(uri.fragment, contains('id='));
    });

    test('o esquema próprio leva os mesmos dados', () {
      final convite = conviteDeExemplo();
      final lido = ConviteLink.decodificar(convite.codificarEsquemaProprio());

      expect(lido, isNotNull);
      expect(lido!.inventarioId, convite.inventarioId);
      expect(lido.dispositivoOrigem, a.dispositivoId);
    });

    test('lê a rota que o go_router entrega, nos dois endereços', () {
      final convite = conviteDeExemplo();
      final parametros = convite.codificar().split('#').last;

      for (final rota in [
        '$caminhoEntrar#$parametros',
        '/entrar#$parametros',
      ]) {
        final lido = ConviteLink.deUri(Uri.parse(rota));
        expect(lido, isNotNull, reason: rota);
        expect(lido!.inventarioId, convite.inventarioId, reason: rota);
      }
    });

    test('aceita os parâmetros na query, se o fragmento se perder', () {
      // Tolerância a aplicativo de mensagens que reescreve o endereço: o
      // fragmento é o lugar certo, mas perdê-lo não pode quebrar a entrada.
      final convite = conviteDeExemplo();
      final parametros = convite.codificar().split('#').last;
      final lido = ConviteLink.decodificar(
        'https://$hostSite$caminhoEntrar?$parametros',
      );

      expect(lido, isNotNull);
      expect(lido!.inventarioId, convite.inventarioId);
    });

    test('nome com espaço e acento atravessa o link', () {
      final convite = ConviteLink.de(
        a.inventarios.criar(nome: 'Reitoria & Anexo — 2ª etapa', ano: 2027),
        dispositivo: a.dispositivoId,
      );
      final lido = ConviteLink.decodificar(convite.codificar());

      expect(lido!.nome, 'Reitoria & Anexo — 2ª etapa');
      expect(lido.ano, 2027);
    });

    test('endereço que não é convite é ignorado em silêncio', () {
      // Abrir um link qualquer no aplicativo é o caso comum, e não é erro.
      for (final endereco in [
        'https://ifpi.edu.br',
        'https://$hostSite/slap-mobile/',
        'https://outro.site$caminhoEntrar#v=2&id=abc',
        '$caminhoEntrar#v=2',
        '$caminhoEntrar#id=abc',
        'slapmobile://outra-coisa#v=2&id=abc',
        '',
      ]) {
        expect(
          ConviteLink.decodificar(endereco),
          isNull,
          reason: 'endereço "$endereco"',
        );
      }
    });

    test('convite sem nome nem ano ainda abre, com rótulo genérico', () {
      final lido = ConviteLink.decodificar(
        'https://$hostSite$caminhoEntrar#v=2&id=abc-123',
      );

      expect(lido, isNotNull);
      expect(lido!.inventarioId, 'abc-123');
      expect(lido.nome, 'Inventário');
      expect(lido.dispositivoOrigem, isNull);
    });
  });

  group('token do pedido', () {
    test('cada pedido nasce com um token diferente', () {
      final tokens = {for (var i = 0; i < 500; i++) gerarTokenEntrada()};
      expect(tokens.length, 500);
    });

    test('o token tem 32 bytes de aleatoriedade', () {
      expect(base64Url.decode(gerarTokenEntrada()).length, 32);
    });
  });

  group('rótulo da entrega', () {
    test('muda com o token, com o inventário e com cada chave pública', () {
      String rotulo({
        String inventario = 'inv',
        String token = 'tok',
        String pedinte = 'pa',
        String origem = 'po',
      }) => rotuloEntrega(
        inventarioId: inventario,
        token: token,
        publicaPedinte: pedinte,
        publicaOrigem: origem,
      );

      final base = rotulo();
      expect(rotulo(inventario: 'outro'), isNot(base));
      expect(rotulo(token: 'outro'), isNot(base));
      expect(rotulo(pedinte: 'outro'), isNot(base));
      expect(rotulo(origem: 'outro'), isNot(base));
      expect(rotulo(), base, reason: 'os dois lados precisam do mesmo rótulo');
    });
  });
}
