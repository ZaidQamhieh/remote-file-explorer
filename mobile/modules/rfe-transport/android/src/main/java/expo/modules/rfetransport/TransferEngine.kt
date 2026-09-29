package expo.modules.rfetransport

import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future

enum class TransferState { QUEUED, RUNNING, PAUSED, DONE, FAILED, CANCELLED }

data class TransferRecord(
  val id: String,
  val hostId: String,
  val address: String,
  val remotePath: String,
  val destPath: String,
  val state: TransferState,
  val received: Long,
  val total: Long,
  val error: String?,
) {
  fun toJson(): JSONObject = JSONObject()
    .put("id", id).put("hostId", hostId).put("address", address).put("remotePath", remotePath)
    .put("destPath", destPath).put("state", state.name).put("received", received).put("total", total)
    .put("error", error ?: JSONObject.NULL)

  companion object {
    fun fromJson(j: JSONObject) = TransferRecord(
      j.getString("id"), j.getString("hostId"), j.getString("address"), j.getString("remotePath"),
      j.getString("destPath"), TransferState.valueOf(j.getString("state")), j.getLong("received"),
      j.getLong("total"), if (j.isNull("error")) null else j.getString("error"),
    )
  }
}

/** Supplies the secure-store pin and token; secrets are never persisted in the journal. */
interface Credentials {
  fun pin(hostId: String): String?
  fun token(hostId: String): String?
}

/**
 * Durable, resumable download engine. Independent of the JS runtime and of any
 * Android UI so a foreground service can keep it alive when the app is
 * backgrounded or killed. State lives in a per-transfer JSON journal; the bytes
 * live in `<dest>.part` and are the source of truth for resume offsets.
 *
 * - Resume: Range from the `.part` length; a 200 to a ranged request restarts
 *   from zero (server ignored Range), never appends full content to a partial.
 * - Integrity: when the server states a length, the final size must match
 *   before the atomic rename; a mismatch fails the transfer and keeps `.part`.
 * - Process death: transfers found RUNNING/QUEUED at startup become PAUSED.
 */
class TransferEngine(
  private val dir: File,
  private val creds: Credentials,
  private val maxConcurrent: Int = 2,
  private val onChange: (TransferRecord) -> Unit = {},
  private val timeoutMs: Long = 30000,
) {
  private val pool = Executors.newFixedThreadPool(maxConcurrent)
  private val records = ConcurrentHashMap<String, TransferRecord>()
  private val futures = ConcurrentHashMap<String, Future<*>>()
  private val calls = ConcurrentHashMap<String, okhttp3.Call>()
  private class Attempt { @Volatile var stop: TransferState? = null }
  private val attempts = ConcurrentHashMap<String, Attempt>()

  init {
    dir.mkdirs()
    dir.listFiles { f -> f.extension == "json" }?.forEach { f ->
      runCatching { TransferRecord.fromJson(JSONObject(f.readText())) }.getOrNull()?.let { r ->
        val fixed = if (r.state == TransferState.RUNNING || r.state == TransferState.QUEUED) r.copy(state = TransferState.PAUSED) else r
        records[fixed.id] = fixed
        if (fixed != r) persist(fixed)
      }
    }
  }

  fun list(): List<TransferRecord> = records.values.sortedBy { it.id }
  fun activeCount(): Int = records.values.count { it.state == TransferState.RUNNING || it.state == TransferState.QUEUED }

  fun enqueue(id: String, hostId: String, address: String, remotePath: String, destPath: String): TransferRecord {
    require(id.matches(Regex("[A-Za-z0-9_-]{1,64}"))) { "invalid transfer id" }
    val r = TransferRecord(id, hostId, address, remotePath, destPath, TransferState.QUEUED, 0, -1, null)
    records[id] = r
    persist(r)
    submit(id)
    return r
  }

  fun resume(id: String) {
    val r = records[id] ?: return
    if (r.state == TransferState.PAUSED || r.state == TransferState.FAILED) {
      update(r.copy(state = TransferState.QUEUED, error = null))
      submit(id)
    }
  }

  fun pause(id: String) = stop(id, TransferState.PAUSED)

  fun cancel(id: String) {
    stop(id, TransferState.CANCELLED)
    records[id]?.let { File(it.destPath + ".part").delete() }
  }

  fun shutdown() {
    pool.shutdownNow()
  }

  private fun stop(id: String, reason: TransferState) {
    val r = records[id] ?: return
    if (r.state == TransferState.DONE) return
    attempts[id]?.stop = reason
    calls[id]?.cancel()
    futures[id]?.cancel(true)
    if (r.state != TransferState.RUNNING) update(r.copy(state = reason))
  }

  private fun submit(id: String) {
    val attempt = Attempt()
    attempts[id] = attempt
    futures[id] = pool.submit { run(id, attempt) }
  }

  private fun run(id: String, attempt: Attempt) {
    var r = records[id] ?: return
    if (attempt.stop != null) return
    r = update(r.copy(state = TransferState.RUNNING, error = null))
    val dest = File(r.destPath)
    val part = File(dest.path + ".part")
    try {
      dest.parentFile?.mkdirs()
      val token = creds.token(r.hostId)
      val headers = mutableMapOf("X-RFE-Client-Version" to "rn")
      if (token != null) headers["Authorization"] = "Bearer $token"
      var offset = if (part.exists()) part.length() else 0L
      if (offset > 0) headers["Range"] = "bytes=$offset-"
      val url = "https://${r.address}/v1/content?path=" + java.net.URLEncoder.encode(r.remotePath, "UTF-8")
      val call = PinnedHttp.newGetCall(url, headers, creds.pin(r.hostId), timeoutMs)
      calls[id] = call
      call.execute().use { resp ->
        if (resp.code == 416 && offset > 0) { // stale/oversized partial: restart cleanly
          part.delete()
          throw RestartFromZero()
        }
        if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
        val resumed = offset > 0 && resp.code == 206
        if (!resumed) offset = 0
        val len = resp.body!!.contentLength()
        val total = if (len >= 0) offset + len else -1L
        var received = offset
        var lastEmit = 0L
        FileOutputStream(part, resumed).use { out ->
          val buf = ByteArray(64 * 1024)
          val src = resp.body!!.byteStream()
          while (true) {
            if (Thread.currentThread().isInterrupted || attempt.stop != null) throw InterruptedException()
            val n = src.read(buf)
            if (n < 0) break
            out.write(buf, 0, n)
            received += n
            val now = System.currentTimeMillis()
            if (now - lastEmit > 250) {
              lastEmit = now
              r = update(r.copy(received = received, total = total))
            }
          }
          out.fd.sync()
        }
        if (total >= 0 && part.length() != total) throw IOException("size mismatch: got ${part.length()} expected $total")
        if (dest.exists()) dest.delete()
        if (!part.renameTo(dest)) throw IOException("could not finalize download")
        update(r.copy(state = TransferState.DONE, received = dest.length(), total = dest.length(), error = null))
      }
    } catch (e: RestartFromZero) {
      if (attempts[id] === attempt) submit(id)
    } catch (e: Exception) {
      if (attempts[id] !== attempt) return // superseded by a newer attempt
      // An interrupt without an explicit stop is engine shutdown: keep the partial, resumable.
      val reason = attempt.stop ?: if (e is InterruptedException || Thread.currentThread().isInterrupted) TransferState.PAUSED else null
      val cur = records[id] ?: return
      if (reason != null) update(cur.copy(state = reason))
      else update(cur.copy(state = TransferState.FAILED, error = describe(e)))
    } finally {
      if (attempts[id] === attempt) calls.remove(id)
    }
  }

  private class RestartFromZero : RuntimeException()

  private fun describe(e: Exception): String = when (e) {
    is CertPinMismatch -> "ERR_CERT_PIN_MISMATCH"
    is PinPolicyViolation -> "ERR_PIN_POLICY"
    is javax.net.ssl.SSLException ->
      if (generateSequence<Throwable>(e) { it.cause }.any { it is CertPinMismatch }) "ERR_CERT_PIN_MISMATCH" else "ERR_TLS"
    is IOException -> "ERR_CONNECTION: ${e.message}"
    else -> e.message ?: e.javaClass.simpleName
  }

  private fun update(r: TransferRecord): TransferRecord {
    records[r.id] = r
    persist(r)
    onChange(r)
    return r
  }

  private fun persist(r: TransferRecord) {
    val tmp = File(dir, "${r.id}.json.tmp")
    tmp.writeText(r.toJson().toString())
    tmp.renameTo(File(dir, "${r.id}.json"))
  }
}
