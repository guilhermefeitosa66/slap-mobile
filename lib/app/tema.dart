/// Linguagem visual do aplicativo.
///
/// Os valores vêm do design das telas
/// (https://claude.ai/artifact/74m64ugT1R5S8Xu1Pb9oP5). O design define o tema
/// claro; o escuro é derivado dele mantendo as mesmas relações — fundo
/// quente, um único teal de ação e os três resultados em tom com texto
/// escuro sobre claro (ou o inverso), nunca texto branco sobre cor sólida.
///
/// Todos os pares de texto e fundo daqui passam de 4.5:1.
library;

import 'package:flutter/material.dart';

import '../data/repos/patrimonios.dart';
import '../domain/divergencia.dart';

// ------------------------------------------------------------------ fontes ---

/// Títulos, números e tombos. Os algarismos da Archivo já são tabulares, de
/// modo que uma coluna de tombos alinha sozinha.
const familiaTitulos = 'Archivo';

/// Corpo e interface.
const familiaTexto = 'Public Sans';

// ------------------------------------------------------------------- cores ---

/// Tokens de cor do tema claro, como estão no design.
class PaletaClara {
  static const fundo = Color(0xFFF7F6F3);
  static const superficie = Color(0xFFFFFFFF);
  static const tinta = Color(0xFF14201E);
  static const tintaSecundaria = Color(0xFF55625F);
  static const teal = Color(0xFF0F5C52);
  static const tealClaro = Color(0xFFDCE9E6);
  static const sobreTealClaro = Color(0xFF0B3B34);
  static const borda = Color(0xFFE2E0DA);
  static const bordaCampo = Color(0xFFD8D5CD);
  static const bordaSegmento = Color(0xFFB9CFCA);
  static const trilho = Color(0xFFEDEBE4);
  static const apagado = Color(0xFF9AA5A2);
  static const aviso = Color(0xFFEFEEE8);
  static const concluido = Color(0xFF15703A);
  static const faixaSecundaria = Color(0xFFC9DED9);
}

/// Tema escuro, derivado do claro.
class PaletaEscura {
  static const fundo = Color(0xFF111816);
  static const superficie = Color(0xFF1A2220);
  static const tinta = Color(0xFFE9EDEB);
  static const tintaSecundaria = Color(0xFFA9B5B2);
  static const teal = Color(0xFF8FCFC2);
  static const sobreTeal = Color(0xFF0B2A25);
  static const tealClaro = Color(0xFF1E3A35);
  static const sobreTealClaro = Color(0xFFCDE8E2);
  static const borda = Color(0xFF2C3633);
  static const bordaCampo = Color(0xFF3A4643);
  static const bordaSegmento = Color(0xFF3F5A55);
  static const trilho = Color(0xFF26302D);
  static const apagado = Color(0xFF6F7C79);
  static const aviso = Color(0xFF1F2725);
  static const concluido = Color(0xFF7FD19A);
  static const faixa = Color(0xFF174C45);
}

/// Um resultado em tom: fundo claro e texto escuro no tema claro, o inverso
/// no escuro.
///
/// É a correção do branco sobre laranja, que não chegava a 4.5:1. O texto de
/// cada tom também serve sozinho sobre o fundo da tela — é como aparece nas
/// listas, em ícone e subtítulo.
@immutable
class TomResultado {
  final Color fundo;
  final Color texto;

  const TomResultado({required this.fundo, required this.texto});

  static TomResultado lerp(TomResultado a, TomResultado b, double t) =>
      TomResultado(
        fundo: Color.lerp(a.fundo, b.fundo, t)!,
        texto: Color.lerp(a.texto, b.texto, t)!,
      );
}

/// Cores dos três resultados de leitura e das classificações.
///
/// Sempre acompanhadas de ícone e texto: cor sozinha não serve a quem tem
/// daltonismo, e o levantamento depende de reconhecer o resultado num relance.
@immutable
class CoresResultado extends ThemeExtension<CoresResultado> {
  final TomResultado registrado;
  final TomResultado jaVerificado;
  final TomResultado naoLocalizado;
  final TomResultado neutro;

  const CoresResultado({
    required this.registrado,
    required this.jaVerificado,
    required this.naoLocalizado,
    required this.neutro,
  });

  static const claro = CoresResultado(
    registrado: TomResultado(
      fundo: Color(0xFFDFF0E4),
      texto: Color(0xFF0F5C2E),
    ),
    jaVerificado: TomResultado(
      fundo: Color(0xFFFBE8D6),
      texto: Color(0xFF8A4408),
    ),
    naoLocalizado: TomResultado(
      fundo: Color(0xFFFAE0DE),
      texto: Color(0xFF7E1214),
    ),
    neutro: TomResultado(fundo: Color(0xFFECEEED), texto: Color(0xFF45514E)),
  );

  static const escuro = CoresResultado(
    registrado: TomResultado(
      fundo: Color(0xFF16341F),
      texto: Color(0xFFA8DDB6),
    ),
    jaVerificado: TomResultado(
      fundo: Color(0xFF3D2410),
      texto: Color(0xFFF3C79B),
    ),
    naoLocalizado: TomResultado(
      fundo: Color(0xFF431A1A),
      texto: Color(0xFFF4B8B3),
    ),
    neutro: TomResultado(fundo: Color(0xFF262E2C), texto: Color(0xFFC3CCCA)),
  );

  static CoresResultado of(BuildContext context) =>
      Theme.of(context).extension<CoresResultado>() ?? claro;

  /// Tom de uma classificação do resultado final.
  TomResultado de(Classificacao c) => switch (c) {
    Classificacao.ok => registrado,
    Classificacao.divergente => jaVerificado,
    Classificacao.naoLocalizado => naoLocalizado,
    Classificacao.ignorado => neutro,
  };

  /// Tom de uma leitura do levantamento.
  TomResultado daLeitura(ResultadoLeitura r) => switch (r) {
    ResultadoLeitura.sucesso => registrado,
    ResultadoLeitura.jaVerificado => jaVerificado,
    ResultadoLeitura.naoLocalizado => naoLocalizado,
  };

  static IconData icone(Classificacao c) => switch (c) {
    Classificacao.ok => Icons.check_circle_outline,
    Classificacao.divergente => Icons.swap_horiz,
    Classificacao.naoLocalizado => Icons.search_off,
    Classificacao.ignorado => Icons.block,
  };

  static IconData iconeDaLeitura(ResultadoLeitura r) => switch (r) {
    ResultadoLeitura.sucesso => Icons.check_circle_outline,
    ResultadoLeitura.jaVerificado => Icons.replay,
    ResultadoLeitura.naoLocalizado => Icons.search_off,
  };

  /// O nome do resultado, como é dito na tela e anunciado pelo leitor de tela.
  static String rotuloDaLeitura(ResultadoLeitura r) => switch (r) {
    ResultadoLeitura.sucesso => 'Registrado',
    ResultadoLeitura.jaVerificado => 'Já verificado',
    ResultadoLeitura.naoLocalizado => 'Não localizado',
  };

  @override
  CoresResultado copyWith({
    TomResultado? registrado,
    TomResultado? jaVerificado,
    TomResultado? naoLocalizado,
    TomResultado? neutro,
  }) {
    return CoresResultado(
      registrado: registrado ?? this.registrado,
      jaVerificado: jaVerificado ?? this.jaVerificado,
      naoLocalizado: naoLocalizado ?? this.naoLocalizado,
      neutro: neutro ?? this.neutro,
    );
  }

  @override
  CoresResultado lerp(CoresResultado? outro, double t) {
    if (outro == null) return this;
    return CoresResultado(
      registrado: TomResultado.lerp(registrado, outro.registrado, t),
      jaVerificado: TomResultado.lerp(jaVerificado, outro.jaVerificado, t),
      naoLocalizado: TomResultado.lerp(naoLocalizado, outro.naoLocalizado, t),
      neutro: TomResultado.lerp(neutro, outro.neutro, t),
    );
  }
}

/// Cores de apoio que o `ColorScheme` não tem onde guardar.
@immutable
class CoresApoio extends ThemeExtension<CoresApoio> {
  /// Faixa da configuração do levantamento: sempre visível, porque enganar-se
  /// ali contamina tudo o que vier depois.
  final Color faixa;
  final Color sobreFaixa;
  final Color sobreFaixaSecundario;

  /// Trilho das barras de progresso e divisórias internas dos cartões.
  final Color trilho;

  /// Barra de progresso de um inventário concluído.
  final Color concluido;

  /// Setas e ícones de navegação, que não carregam informação.
  final Color apagado;

  /// Quadro de orientação, mais discreto que um cartão.
  final Color aviso;

  const CoresApoio({
    required this.faixa,
    required this.sobreFaixa,
    required this.sobreFaixaSecundario,
    required this.trilho,
    required this.concluido,
    required this.apagado,
    required this.aviso,
  });

  static const claro = CoresApoio(
    faixa: PaletaClara.teal,
    sobreFaixa: Colors.white,
    sobreFaixaSecundario: PaletaClara.faixaSecundaria,
    trilho: PaletaClara.trilho,
    concluido: PaletaClara.concluido,
    apagado: PaletaClara.apagado,
    aviso: PaletaClara.aviso,
  );

  static const escuro = CoresApoio(
    faixa: PaletaEscura.faixa,
    sobreFaixa: Colors.white,
    sobreFaixaSecundario: PaletaClara.faixaSecundaria,
    trilho: PaletaEscura.trilho,
    concluido: PaletaEscura.concluido,
    apagado: PaletaEscura.apagado,
    aviso: PaletaEscura.aviso,
  );

  static CoresApoio of(BuildContext context) =>
      Theme.of(context).extension<CoresApoio>() ?? claro;

  @override
  CoresApoio copyWith({
    Color? faixa,
    Color? sobreFaixa,
    Color? sobreFaixaSecundario,
    Color? trilho,
    Color? concluido,
    Color? apagado,
    Color? aviso,
  }) {
    return CoresApoio(
      faixa: faixa ?? this.faixa,
      sobreFaixa: sobreFaixa ?? this.sobreFaixa,
      sobreFaixaSecundario: sobreFaixaSecundario ?? this.sobreFaixaSecundario,
      trilho: trilho ?? this.trilho,
      concluido: concluido ?? this.concluido,
      apagado: apagado ?? this.apagado,
      aviso: aviso ?? this.aviso,
    );
  }

  @override
  CoresApoio lerp(CoresApoio? outro, double t) {
    if (outro == null) return this;
    return CoresApoio(
      faixa: Color.lerp(faixa, outro.faixa, t)!,
      sobreFaixa: Color.lerp(sobreFaixa, outro.sobreFaixa, t)!,
      sobreFaixaSecundario: Color.lerp(
        sobreFaixaSecundario,
        outro.sobreFaixaSecundario,
        t,
      )!,
      trilho: Color.lerp(trilho, outro.trilho, t)!,
      concluido: Color.lerp(concluido, outro.concluido, t)!,
      apagado: Color.lerp(apagado, outro.apagado, t)!,
      aviso: Color.lerp(aviso, outro.aviso, t)!,
    );
  }
}

// ------------------------------------------------------------------- tema ---

/// Alvo mínimo de toque. O levantamento é feito em pé, andando, muitas vezes
/// com uma das mãos ocupada pelo leitor de código de barras.
const double alvoMinimo = 48;

const _raioCartao = 16.0;
const _raioControle = 12.0;

ThemeData _tema(Brightness brilho) {
  final claro = brilho == Brightness.light;

  final fundo = claro ? PaletaClara.fundo : PaletaEscura.fundo;
  final superficie = claro ? PaletaClara.superficie : PaletaEscura.superficie;
  final tinta = claro ? PaletaClara.tinta : PaletaEscura.tinta;
  final secundaria = claro
      ? PaletaClara.tintaSecundaria
      : PaletaEscura.tintaSecundaria;
  final teal = claro ? PaletaClara.teal : PaletaEscura.teal;
  final sobreTeal = claro ? Colors.white : PaletaEscura.sobreTeal;
  final borda = claro ? PaletaClara.borda : PaletaEscura.borda;
  final bordaCampo = claro ? PaletaClara.bordaCampo : PaletaEscura.bordaCampo;
  final resultados = claro ? CoresResultado.claro : CoresResultado.escuro;
  final apoio = claro ? CoresApoio.claro : CoresApoio.escuro;

  final esquema =
      ColorScheme.fromSeed(
        seedColor: PaletaClara.teal,
        brightness: brilho,
      ).copyWith(
        primary: teal,
        onPrimary: sobreTeal,
        primaryContainer: claro
            ? PaletaClara.tealClaro
            : PaletaEscura.tealClaro,
        onPrimaryContainer: claro
            ? PaletaClara.sobreTealClaro
            : PaletaEscura.sobreTealClaro,
        secondary: teal,
        onSecondary: sobreTeal,
        secondaryContainer: claro
            ? PaletaClara.tealClaro
            : PaletaEscura.tealClaro,
        onSecondaryContainer: claro
            ? PaletaClara.sobreTealClaro
            : PaletaEscura.sobreTealClaro,
        error: resultados.naoLocalizado.texto,
        onError: claro ? Colors.white : resultados.naoLocalizado.fundo,
        errorContainer: resultados.naoLocalizado.fundo,
        onErrorContainer: resultados.naoLocalizado.texto,
        surface: fundo,
        onSurface: tinta,
        onSurfaceVariant: secundaria,
        surfaceContainerLowest: superficie,
        surfaceContainerLow: superficie,
        outline: claro ? PaletaClara.apagado : PaletaEscura.apagado,
        outlineVariant: borda,
      );

  TextStyle titulo(double tamanho, FontWeight peso, {double? espaco}) =>
      TextStyle(
        fontFamily: familiaTitulos,
        fontSize: tamanho,
        fontWeight: peso,
        letterSpacing: espaco,
        color: tinta,
        height: 1.2,
      );

  TextStyle texto(double tamanho, FontWeight peso, {Color? cor}) => TextStyle(
    fontFamily: familiaTexto,
    fontSize: tamanho,
    fontWeight: peso,
    color: cor ?? tinta,
    height: 1.4,
  );

  final tipografia = TextTheme(
    displayLarge: titulo(57, FontWeight.w700, espaco: -1.1),
    displayMedium: titulo(48, FontWeight.w700, espaco: -1),
    displaySmall: titulo(44, FontWeight.w700, espaco: -0.9),
    headlineLarge: titulo(32, FontWeight.w700, espaco: -0.6),
    headlineMedium: titulo(26, FontWeight.w700, espaco: -0.4),
    headlineSmall: titulo(22, FontWeight.w700, espaco: -0.2),
    titleLarge: titulo(19, FontWeight.w600),
    titleMedium: titulo(17, FontWeight.w600),
    titleSmall: texto(15, FontWeight.w600),
    bodyLarge: texto(16, FontWeight.w400),
    bodyMedium: texto(14.5, FontWeight.w400),
    bodySmall: texto(12.5, FontWeight.w400, cor: secundaria),
    labelLarge: texto(15, FontWeight.w600),
    labelMedium: texto(13, FontWeight.w600, cor: secundaria),
    labelSmall: texto(12, FontWeight.w500, cor: secundaria),
  );

  final formaControle = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_raioControle),
  );

  OutlineInputBorder bordaDeCampo(Color cor, double largura) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_raioControle),
        borderSide: BorderSide(color: cor, width: largura),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brilho,
    colorScheme: esquema,
    fontFamily: familiaTexto,
    textTheme: tipografia,
    scaffoldBackgroundColor: fundo,
    canvasColor: fundo,
    dividerColor: borda,
    // Padrão, e não "comfortable": o compacto encolhe os controles abaixo do
    // alvo de 48 px que o design exige.
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [resultados, apoio],
    appBarTheme: AppBarTheme(
      backgroundColor: fundo,
      foregroundColor: tinta,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: titulo(18, FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_raioCartao),
        side: BorderSide(color: borda),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: formaControle,
        textStyle: texto(16, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(alvoMinimo, alvoMinimo),
        foregroundColor: teal,
        side: BorderSide(color: teal, width: 1.5),
        shape: formaControle,
        textStyle: texto(15, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(alvoMinimo, alvoMinimo),
        foregroundColor: teal,
        textStyle: texto(15, FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(alvoMinimo, alvoMinimo),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: teal,
      foregroundColor: sobreTeal,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: texto(16, FontWeight.w600),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(alvoMinimo, alvoMinimo),
        backgroundColor: superficie,
        foregroundColor: tinta,
        selectedBackgroundColor: teal,
        selectedForegroundColor: sobreTeal,
        side: BorderSide(
          color: claro ? PaletaClara.bordaSegmento : PaletaEscura.bordaSegmento,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: texto(14, FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: superficie,
      selectedColor: teal,
      checkmarkColor: sobreTeal,
      side: BorderSide(color: bordaCampo),
      shape: const StadiumBorder(),
      labelStyle: texto(13.5, FontWeight.w500),
      secondaryLabelStyle: texto(13.5, FontWeight.w600, cor: sobreTeal),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: bordaDeCampo(bordaCampo, 1.5),
      enabledBorder: bordaDeCampo(bordaCampo, 1.5),
      focusedBorder: bordaDeCampo(teal, 2),
      errorBorder: bordaDeCampo(resultados.naoLocalizado.texto, 1.5),
      focusedErrorBorder: bordaDeCampo(resultados.naoLocalizado.texto, 2),
      labelStyle: texto(15, FontWeight.w500, cor: secundaria),
      floatingLabelStyle: texto(14, FontWeight.w600, cor: teal),
      hintStyle: texto(15, FontWeight.w400, cor: secundaria),
      helperStyle: texto(12.5, FontWeight.w400, cor: secundaria),
      prefixIconColor: secundaria,
      suffixIconColor: secundaria,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minTileHeight: alvoMinimo + 8,
      iconColor: teal,
      titleTextStyle: texto(15, FontWeight.w500),
      subtitleTextStyle: texto(12.5, FontWeight.w400, cor: secundaria),
    ),
    dividerTheme: DividerThemeData(color: borda, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: apoio.trilho,
      circularTrackColor: apoio.trilho,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: claro ? PaletaClara.tinta : PaletaEscura.superficie,
      contentTextStyle: texto(14.5, FontWeight.w500, cor: PaletaEscura.tinta),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_raioControle),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: fundo,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: bordaCampo,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: fundo,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: titulo(20, FontWeight.w700),
      contentTextStyle: texto(15, FontWeight.w400),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: resultados.naoLocalizado.fundo,
      contentTextStyle: texto(
        14,
        FontWeight.w500,
        cor: resultados.naoLocalizado.texto,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
  );
}

final temaClaro = _tema(Brightness.light);
final temaEscuro = _tema(Brightness.dark);

/// Estilo de tombo e código: Archivo, com os algarismos tabulares que a fonte
/// já traz por padrão.
TextStyle estiloCodigo(BuildContext context, {double tamanho = 15}) {
  return TextStyle(
    fontFamily: familiaTitulos,
    fontSize: tamanho,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: Theme.of(context).colorScheme.onSurface,
  );
}
