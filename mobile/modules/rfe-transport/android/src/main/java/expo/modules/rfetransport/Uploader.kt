package expo.modules.rfetransport

import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest

/** The agent refused the upload with a definite answer; [message] is its API error code (CONFLICT, HASH_MISMATCH...). */
class UploadRejected(val status: Int, code: String) : IOException(code.ifEmpty { "HTTP $status" })

/**
 * One resumable chunked upload against the agent's `/v1/transfers` session API.
 *
 * The whole file is hashed once (and the digest kept in the journal); each chunk carries its own SHA-256 and the
 * agent verifies both, so a corrupt byte anywhere fails loudly instead of landing on the host. Resume asks the agent
 * which chunks it already holds (its bitmap) and sends only the rest. Chunk sends retry on transport errors and on a
 * chunk hash mismatch; any other agent answer is final.
 */
class Uploader(
  private val creds: Credentials,
  private val timeoutMs: Long,
  private val stopped: () -> Boolean,
  private val track: (Call) -> Unit,
  private val save: (TransferRecord) -> Unit,
  private val chunkSize: Int = 4 * 1024 * 1024,
  private val chunkRetries: Int = 3,
) {
  private class Session(val id: String, val chunkSize: Int, val totalChunks: Int, val received: Set<Int>, val open: Boolean)

  fun run(start: TransferRecord): TransferRecord {
    var r = start
    val src = File(r.destPath)
    if (!src.isFile) throw IOException("source file is missing")
    val size = src.length()
    if (r.sha256 == null || r.total != size) {
      // First run, or the source changed since it was hashed: any old session describes different bytes.
      r = r.copy(sha256 = sha256Of(src), total = size, sessionId = null)
      save(r)
    }
    var session: Session? = r.sessionId?.let { existing(r, it) }
    if (session == null) {
      session = open(r, size)
      r = r.copy(sessionId = session.id)
      save(r)
    }
    var sent = session.received.sumOf { chunkLen(it, size, session.chunkSize, session.totalChunks) }
    r = r.copy(received = sent)
    save(r)
    RandomAccessFile(src, "r").use { f ->
      for (n in 0 until session.totalChunks) {
        if (n in session.received) continue
        if (stopped()) throw InterruptedException()
        val len = chunkLen(n, size, session.chunkSize, session.totalChunks).toInt()
        val buf = ByteArray(len)
        f.seek(n.toLong() * session.chunkSize)
        f.readFully(buf)
        putChunk(r, session.id, n, buf)
        sent += len
        r = r.copy(received = sent)
        save(r)
      }
    }
    if (stopped()) throw InterruptedException()
    complete(r, session.id)
    return r.copy(received = size)
  }

  private fun chunkLen(n: Int, size: Long, chunk: Int, total: Int): Long =
    if (size == 0L) 0 else if (n == total - 1) size - n.toLong() * chunk else chunk.toLong()

  private fun sha256Of(f: File): String {
    val md = MessageDigest.getInstance("SHA-256")
    f.inputStream().use { input ->
      val buf = ByteArray(64 * 1024)
      while (true) {
        if (stopped()) throw InterruptedException()
        val n = input.read(buf)
        if (n < 0) break
        md.update(buf, 0, n)
      }
    }
    return md.digest().joinToString("") { "%02x".format(it) }
  }

  private class Reply(val status: Int, val body: String) {
    fun json(): JSONObject = JSONObject(body)
    fun code(): String = runCatching { JSONObject(body).optString("code") }.getOrDefault("")
  }

  private fun send(r: TransferRecord, method: String, path: String, json: JSONObject? = null, raw: ByteArray? = null, extra: Map<String, String> = emptyMap()): Reply {
    val headers = mutableMapOf("X-RFE-Client-Version" to "rn")
    creds.token(r.hostId)?.let { headers["Authorization"] = "Bearer $it" }
    headers.putAll(extra)
    val body = when {
      json != null -> json.toString().toRequestBody("application/json".toMediaTypeOrNull())
      raw != null -> raw.toRequestBody("application/octet-stream".toMediaTypeOrNull())
      else -> null
    }
    val call = PinnedHttp.newCall(method, "https://${r.address}/v1$path", headers, body, creds.pin(r.hostId), timeoutMs)
    track(call)
    call.execute().use { resp -> return Reply(resp.code, resp.body?.string() ?: "") }
  }

  private fun rejected(reply: Reply): Nothing = throw UploadRejected(reply.status, reply.code())

  private fun parse(reply: Reply): Session {
    val j = reply.json()
    val got = j.optJSONArray("receivedChunks") ?: JSONArray()
    return Session(j.getString("id"), j.getInt("chunkSize"), j.getInt("totalChunks"), (0 until got.length()).map { got.getInt(it) }.toSet(), j.optString("status", "open") == "open")
  }

  /** The saved session if the agent still holds it and it is open; null means open a new one. */
  private fun existing(r: TransferRecord, id: String): Session? {
    val reply = send(r, "GET", "/transfers/$id")
    if (reply.status == 404) return null
    if (reply.status != 200) rejected(reply)
    return parse(reply).takeIf { it.open }
  }

  private fun open(r: TransferRecord, size: Long): Session {
    val reply = send(r, "POST", "/transfers", json = JSONObject()
      .put("path", r.remotePath).put("size", size).put("sha256", r.sha256).put("chunkSize", chunkSize).put("overwrite", r.overwrite))
    if (reply.status != 201) rejected(reply)
    return parse(reply)
  }

  private fun putChunk(r: TransferRecord, id: String, n: Int, data: ByteArray) {
    val sum = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
    var attempt = 0
    while (true) {
      if (stopped()) throw InterruptedException()
      try {
        val reply = send(r, "PUT", "/transfers/$id/chunks/$n", raw = data, extra = mapOf("X-Chunk-Sha256" to sum))
        if (reply.status == 204) return
        // A corrupted or torn chunk is worth sending again; every other answer is the agent's decision.
        if (reply.code() != "CHUNK_HASH_MISMATCH" || attempt >= chunkRetries) rejected(reply)
      } catch (e: UploadRejected) {
        throw e
      } catch (e: IOException) {
        if (stopped() || e is javax.net.ssl.SSLException || attempt >= chunkRetries) throw e
      }
      attempt++
      Thread.sleep(200L * attempt)
    }
  }

  private fun complete(r: TransferRecord, id: String) {
    val reply = send(r, "POST", "/transfers/$id/complete")
    if (reply.status != 200) rejected(reply)
  }
}
