import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/banco.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // O levantamento é feito com o celular na mão, apontando para etiquetas.
  // Girar a tela no meio da leitura atrapalha mais do que ajuda.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // O banco abre antes da primeira tela: todas as consultas são síncronas, e
  // nenhuma tela precisa tratar estado de carregamento por causa disso.
  final banco = await Banco.abrir();

  runApp(
    ProviderScope(
      overrides: [bancoProvider.overrideWithValue(banco)],
      child: const AplicativoSlap(),
    ),
  );
}
