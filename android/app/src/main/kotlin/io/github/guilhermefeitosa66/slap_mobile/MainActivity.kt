package io.github.guilhermefeitosa66.slap_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /**
     * Trava de multicast do Wi-Fi.
     *
     * Sem ela o Android descarta os pacotes multicast no nível do Wi-Fi, para
     * economizar bateria: o beacon UDP da descoberta envia, mas nunca recebe.
     * Fica adquirida só enquanto a tela de sincronização procura aparelhos.
     */
    private var travaMulticast: WifiManager.MulticastLock? = null

    /**
     * Arquivo de inventário aberto de fora ("Abrir com" no WhatsApp, no
     * gerenciador de arquivos). Copiado para a pasta temporária e entregue ao
     * Dart: pelo método `pendente` quando abriu o aplicativo, pelo `recebido`
     * quando o aplicativo já estava aberto.
     */
    private var arquivoPendente: String? = null
    private var canalRecebidos: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Antes do super: o Flutter lê o `intent.data` como rota inicial, e
        // um content:// do WhatsApp viraria uma rota que não existe.
        if (savedInstanceState == null) arquivoPendente = receberArquivo(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        val caminho = receberArquivo(intent)
        if (caminho == null) {
            super.onNewIntent(intent)
            return
        }
        setIntent(intent)
        val canal = canalRecebidos
        if (canal == null) arquivoPendente = caminho
        else canal.invokeMethod("recebido", caminho)
    }

    override fun getInitialRoute(): String? =
        if (ehArquivo(intent)) "/" else super.getInitialRoute()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        canalRecebidos = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_RECEBIDOS)
            .also { canal ->
                canal.setMethodCallHandler { chamada, resultado ->
                    when (chamada.method) {
                        "pendente" -> {
                            resultado.success(arquivoPendente)
                            arquivoPendente = null
                        }
                        else -> resultado.notImplemented()
                    }
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_REDE)
            .setMethodCallHandler { chamada, resultado ->
                when (chamada.method) {
                    "adquirirMulticast" -> {
                        val falha = adquirirMulticast()
                        if (falha == null) {
                            resultado.success(true)
                        } else {
                            resultado.error("multicast_indisponivel", falha, null)
                        }
                    }
                    "liberarMulticast" -> {
                        liberarMulticast()
                        resultado.success(null)
                    }
                    else -> resultado.notImplemented()
                }
            }

        // Tela ligada durante o levantamento. A flag vale só enquanto a janela
        // está visível: sair do aplicativo devolve o bloqueio normal sozinho.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_TELA)
            .setMethodCallHandler { chamada, resultado ->
                when (chamada.method) {
                    "manterLigada" -> {
                        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        if (chamada.arguments as? Boolean == true) {
                            window.addFlags(flag)
                        } else {
                            window.clearFlags(flag)
                        }
                        resultado.success(null)
                    }
                    else -> resultado.notImplemented()
                }
            }
    }

    /** Devolve `null` quando a trava ficou adquirida, ou o motivo da falha. */
    private fun adquirirMulticast(): String? {
        travaMulticast?.let { if (it.isHeld) return null }

        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return "WifiManager indisponível neste aparelho"

        return try {
            val trava = wifi.createMulticastLock("slap-descoberta")
            // Sem contagem de referência: uma liberação solta de vez, mesmo
            // que a descoberta tenha sido iniciada duas vezes.
            trava.setReferenceCounted(false)
            trava.acquire()
            travaMulticast = trava
            if (trava.isHeld) null else "o sistema não concedeu a trava"
        } catch (e: SecurityException) {
            "sem a permissão CHANGE_WIFI_MULTICAST_STATE: ${e.message}"
        } catch (e: RuntimeException) {
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun liberarMulticast() {
        try {
            travaMulticast?.let { if (it.isHeld) it.release() }
        } catch (e: RuntimeException) {
            // Já liberada pelo sistema: nada a fazer.
        }
        travaMulticast = null
    }

    /** O arquivo que veio no intent, ou `null` se o intent não traz arquivo. */
    private fun uriDoArquivo(intent: Intent?): Uri? {
        intent ?: return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
            else -> null
        }
        // Os links de convite (https, slapmobile) seguem pelo caminho do Flutter.
        return uri?.takeIf { it.scheme == "content" || it.scheme == "file" }
    }

    private fun ehArquivo(intent: Intent?) = uriDoArquivo(intent) != null

    /** Copia o arquivo do intent para a pasta temporária e devolve o caminho. */
    private fun receberArquivo(intent: Intent?): String? {
        val uri = uriDoArquivo(intent) ?: return null
        return try {
            val destino = File(cacheDir, "recebido-${System.nanoTime()}.db")
            contentResolver.openInputStream(uri)?.use { entrada ->
                destino.outputStream().use { saida -> entrada.copyTo(saida) }
            } ?: return null
            destino.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    override fun onDestroy() {
        // Trava esquecida consome bateria mesmo com o aplicativo fechado.
        liberarMulticast()
        super.onDestroy()
    }

    private companion object {
        const val CANAL_REDE = "slap/rede"
        const val CANAL_TELA = "slap/tela"
        const val CANAL_RECEBIDOS = "slap/recebidos"
    }
}
