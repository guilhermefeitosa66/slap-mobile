package io.github.guilhermefeitosa66.slap_mobile

import android.content.Context
import android.net.wifi.WifiManager
import android.view.WindowManager
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

    override fun onDestroy() {
        // Trava esquecida consome bateria mesmo com o aplicativo fechado.
        liberarMulticast()
        super.onDestroy()
    }

    private companion object {
        const val CANAL_REDE = "slap/rede"
        const val CANAL_TELA = "slap/tela"
    }
}
