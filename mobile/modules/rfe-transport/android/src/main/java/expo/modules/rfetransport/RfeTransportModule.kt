package expo.modules.rfetransport

import android.util.Base64
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File

class RfeTransportModule : Module() {
  private var discovery: LanDiscovery? = null
  private val secure by lazy {
    LegacySecureStore(appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null))
  }

  private fun <T> guard(block: () -> T): T = try {
    block()
  } catch (e: CertPinMismatch) {
    throw CodedException("ERR_CERT_PIN_MISMATCH", e.message, e)
  } catch (e: PinPolicyViolation) {
    throw CodedException("ERR_PIN_POLICY", e.message, e)
  } catch (e: javax.net.ssl.SSLException) {
    // Any TLS failure is fatal for this route; a pin mismatch surfaces as
    // CertPinMismatch (possibly wrapped) and must never look like "unreachable".
    val mismatch = generateSequence<Throwable>(e) { it.cause }.any { it is CertPinMismatch }
    if (mismatch) throw CodedException("ERR_CERT_PIN_MISMATCH", e.message, e)
    throw CodedException("ERR_TLS", e.message, e)
  } catch (e: java.io.IOException) {
    throw CodedException("ERR_CONNECTION", e.message, e)
  }

  override fun definition() = ModuleDefinition {
    Name("RfeTransport")
    Events("onTransferUpdate")

    OnCreate {
      TransferHost.listener = { r -> sendEvent("onTransferUpdate", mapOf("record" to r.toJson().toString())) }
    }
    OnDestroy { TransferHost.listener = null }

    AsyncFunction("transferEnqueue") { id: String, hostId: String, address: String, remotePath: String, destPath: String ->
      val ctx = appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null)
      TransferHost.ensureServiceRunning(ctx)
      TransferHost.engine(ctx).enqueue(id, hostId, address, remotePath, destPath).toJson().toString()
    }
    AsyncFunction("transferResume") { id: String ->
      val ctx = appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null)
      TransferHost.ensureServiceRunning(ctx)
      TransferHost.engine(ctx).resume(id)
    }
    AsyncFunction("transferPause") { id: String ->
      TransferHost.engine(appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null)).pause(id)
    }
    AsyncFunction("transferCancel") { id: String ->
      TransferHost.engine(appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null)).cancel(id)
    }
    AsyncFunction("transfersList") {
      TransferHost.engine(appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null))
        .list().map { it.toJson().toString() }
    }

    AsyncFunction("sendWakeOnLan") { mac: String -> Wol.send(mac) }

    AsyncFunction("deviceId") {
      val ctx = appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null)
      // Settings.Secure.ANDROID_ID: stable per device+signing key; lets a re-pair reuse the same device row.
      android.provider.Settings.Secure.getString(ctx.contentResolver, android.provider.Settings.Secure.ANDROID_ID)
    }

    AsyncFunction("discoveryScan") { promise: expo.modules.kotlin.Promise ->
      val ctx = appContext.reactContext ?: return@AsyncFunction promise.reject(CodedException("ERR_NO_CONTEXT", "no context", null))
      val d = discovery ?: LanDiscovery(ctx).also { discovery = it }
      d.scan { agents, err ->
        if (err != null) promise.reject(CodedException(err, "Local network search failed", null)) else promise.resolve(agents)
      }
    }
    AsyncFunction("discoveryStop") { discovery?.stop() }

    AsyncFunction("legacyPrefsReadAll") {
      LegacyPrefs.readAll(appContext.reactContext ?: throw CodedException("ERR_NO_CONTEXT", "no context", null))
    }

    AsyncFunction("secureRead") { key: String -> secure.read(key) }
    AsyncFunction("secureWrite") { key: String, value: String -> secure.write(key, value) }
    AsyncFunction("secureDelete") { key: String -> secure.delete(key) }
    AsyncFunction("secureContains") { key: String -> secure.contains(key) }

    AsyncFunction("probeFingerprint") { url: String, timeoutMs: Double? ->
      guard { PinnedHttp.probeFingerprint(url, (timeoutMs ?: 8000.0).toLong()) }
    }

    AsyncFunction("request") { url: String, method: String, headers: Map<String, String>,
                               bodyText: String?, pin: String?, timeoutMs: Double? ->
      guard {
        val r = PinnedHttp.request(
          url, method, headers,
          bodyText?.toByteArray(Charsets.UTF_8),
          pin, (timeoutMs ?: 30000.0).toLong(),
        )
        mapOf(
          "status" to r.status,
          "headers" to r.headers,
          "bodyText" to String(r.body, Charsets.UTF_8),
          "seenFingerprint" to r.seenFingerprint,
        )
      }
    }

    AsyncFunction("downloadToFile") { url: String, headers: Map<String, String>, pin: String?,
                                      destPath: String, offset: Double?, timeoutMs: Double? ->
      guard {
        PinnedHttp.downloadToFile(
          url, headers, pin, File(destPath), (offset ?: 0.0).toLong(), (timeoutMs ?: 30000.0).toLong(),
        ).toDouble()
      }
    }
  }
}
