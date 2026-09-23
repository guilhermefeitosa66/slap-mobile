import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/banco.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registrarLicencasDasFontes();

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

/// As fontes são OFL: a licença precisa acompanhar o aplicativo, e a tela de
/// licenças do Flutter é o lugar em que o usuário a encontra.
void _registrarLicencasDasFontes() {
  LicenseRegistry.addLicense(() async* {
    for (final (familia, arquivo) in [
      ('Archivo', 'assets/fontes/OFL-Archivo.txt'),
      ('Public Sans', 'assets/fontes/OFL-PublicSans.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        familia,
      ], await rootBundle.loadString(arquivo));
    }
  });
}
