package expo.modules.rfetransport

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HeldCertificate
import okhttp3.tls.HandshakeCertificates
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException

/**
 * Pinning conformance (spike 1A / CI guard): a host whose leaf does not match
 * the saved pin must observe ZERO application bytes.
 */
class PinnedHttpTest {
  private lateinit var server: MockWebServer
  private lateinit var leaf: HeldCertificate
  private lateinit var url: String

  @Before fun setUp() {
    leaf = HeldCertificate.Builder().commonName("rfe-host").addSubjectAlternativeName("localhost").build()
    val certs = HandshakeCertificates.Builder().heldCertificate(leaf).build()
    server = MockWebServer()
    server.useHttps(certs.sslSocketFactory(), false)
    server.start()
    url = server.url("/health").toString()
  }

  @After fun tearDown() { server.shutdown() }

  private fun pin() = PinnedHttp.sha256Hex(leaf.certificate.encoded)

  @Test fun matchingPinSendsRequestAndReturnsBody() {
    server.enqueue(MockResponse().setBody("ok"))
    val r = PinnedHttp.request(url, "GET", mapOf("Authorization" to "Bearer t"), null, pin())
    assertEquals(200, r.status)
    assertEquals("ok", String(r.body))
    assertEquals(pin(), r.seenFingerprint)
    assertEquals("Bearer t", server.takeRequest().getHeader("Authorization"))
  }

  @Test fun colonSeparatedUppercasePinIsNormalized() {
    server.enqueue(MockResponse().setBody("ok"))
    val fp = pin().uppercase().chunked(2).joinToString(":")
    assertEquals(200, PinnedHttp.request(url, "GET", emptyMap(), null, fp).status)
  }

  @Test fun changedPinFailsBeforeAnyApplicationByte() {
    server.enqueue(MockResponse().setBody("secret"))
    val wrong = "0".repeat(64)
    val ex = assertThrows(Exception::class.java) {
      PinnedHttp.request(url, "POST", mapOf("Authorization" to "Bearer secret-token"), "pairing-code".toByteArray(), wrong)
    }
    assertTrue(ex is SSLHandshakeException || ex is SSLPeerUnverifiedException || ex.cause is CertPinMismatch || ex is CertPinMismatch)
    assertEquals("server must see no HTTP request", 0, server.requestCount)
  }

  @Test fun missingOrInvalidPinIsRefusedWithoutConnecting() {
    val fs = server.url("/v1/fs").toString()
    assertThrows(PinPolicyViolation::class.java) { PinnedHttp.request(fs, "GET", emptyMap(), null, null) }
    assertThrows(PinPolicyViolation::class.java) { PinnedHttp.request(fs, "GET", emptyMap(), null, "abc") }
    assertEquals(0, server.requestCount)
  }

  @Test fun unpinnedPreflightAllowedOnlyForHealthAndChallengeWithoutCredentials() {
    server.enqueue(MockResponse().setBody("{}"))
    server.enqueue(MockResponse().setBody("{}"))
    val base = server.url("/").toString().trimEnd('/')
    assertEquals(200, PinnedHttp.request("$base/v1/health", "GET", emptyMap(), null, null).status)
    assertEquals(200, PinnedHttp.request("$base/v1/auth/challenge", "POST", emptyMap(), null, null).status)
    assertEquals(2, server.requestCount)
    // a bearer token must never ride an unpinned call, even to an allowed path
    assertThrows(PinPolicyViolation::class.java) {
      PinnedHttp.request("$base/v1/health", "GET", mapOf("Authorization" to "Bearer t"), null, null)
    }
    assertThrows(PinPolicyViolation::class.java) { PinnedHttp.request("$base/v1/fs", "GET", emptyMap(), null, null) }
    assertThrows(PinPolicyViolation::class.java) { PinnedHttp.request("$base/v1/pair", "POST", emptyMap(), null, null) }
    assertEquals(2, server.requestCount)
  }

  @Test fun cleartextIsRefused() {
    assertThrows(PinPolicyViolation::class.java) {
      PinnedHttp.request("http://127.0.0.1:1/health", "GET", emptyMap(), null, pin())
    }
  }

  @Test fun probeReturnsFingerprintWithoutSendingHttp() {
    val fp = PinnedHttp.probeFingerprint(url)
    assertEquals(pin(), fp)
    assertEquals(0, server.requestCount)
  }

  @Test fun publicTrustDoesNotBypassPin() {
    // system roots are empty: a wrong pin fails even though TLS itself is fine
    server.enqueue(MockResponse().setBody("x"))
    assertThrows(Exception::class.java) { PinnedHttp.request(url, "GET", emptyMap(), null, "f".repeat(64)) }
    assertEquals(0, server.requestCount)
  }

  @Test fun redirectsAreNotFollowed() {
    server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "https://evil.example/"))
    val r = PinnedHttp.request(url, "GET", emptyMap(), null, pin())
    assertEquals(302, r.status)
    assertNull(r.headers["x-none"])
    assertNotNull(r.headers["location"])
  }

  @Test fun downloadResumesWithRangeAndFinalizesAtomically() {
    val dest = java.io.File.createTempFile("rfe-dl", ".bin"); dest.delete()
    server.enqueue(MockResponse().setBody("hello world"))
    val n = PinnedHttp.downloadToFile(url, emptyMap(), pin(), dest)
    assertEquals(11L, n)
    assertEquals("hello world", dest.readText())
    assertTrue(!java.io.File(dest.path + ".part").exists())
    dest.delete()
  }

  @Test fun downloadSendsRangeHeaderWhenResuming() {
    val dest = java.io.File.createTempFile("rfe-dl", ".bin"); dest.delete()
    server.enqueue(MockResponse().setResponseCode(206).setBody("world"))
    PinnedHttp.downloadToFile(url, emptyMap(), pin(), dest, offset = 6)
    assertEquals("bytes=6-", server.takeRequest().getHeader("Range"))
    dest.delete()
  }
}
