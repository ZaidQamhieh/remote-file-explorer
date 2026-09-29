package expo.modules.rfetransport

import android.util.Base64
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File

class RfeTransportModule : Module() {
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
