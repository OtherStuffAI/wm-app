package com.wingmanbefree.wingman_app.fips

internal object FipsPlatformContract {
    const val CHANNEL = "com.wingmanbefree.wingman_app/fips"
    const val BOOTSTRAP_NPUB =
        "npub1qmc3cvfz0yu2hx96nq3gp55zdan2qclealn7xshgr448d3nh6lks7zel98"
    const val DNS_ADDRESS = "10.1.1.1"
    const val VPN_ADDRESS = "10.1.1.2"
    const val MESH_ROUTE = "fd00::"

    val vpnSpec = VpnSpec(
        ipv6Prefix = 128,
        meshPrefix = 8,
        dnsPrefix = 32,
        mtu = 1280,
        disallowedApplications = emptyList(),
    )

    fun peerStatus(raw: String): Map<String, Any?> {
        val text = raw.lowercase()
        val marker = text.indexOf(BOOTSTRAP_NPUB)
        val peerObject = if (marker >= 0) {
            val start = text.lastIndexOf('{', marker).coerceAtLeast(0)
            val end = text.indexOf('}', marker).let { if (it < 0) text.length else it + 1 }
            text.substring(start, end)
        } else {
            ""
        }
        val connected = Regex("""[\"']connectivity[\"']\s*:\s*[\"']connected[\"']""")
            .containsMatchIn(peerObject)
        return mapOf(
            "connected" to connected,
            "detail" to if (connected) {
                "Authenticated Wingman bootstrap connected."
            } else {
                "Waiting for authenticated Wingman bootstrap over UDP 2121."
            },
        )
    }

    fun probe(raw: String): Map<String, Any?> {
        val overall = Regex("""[\"']overall[\"']\s*:\s*[\"']([^\"']+)[\"']""")
            .find(raw)?.groupValues?.getOrNull(1)
        return mapOf(
            "ok" to (overall == "ok"),
            "detail" to when (overall) {
                null, "" -> "FIPS probe failed."
                else -> "FIPS probe completed: $overall."
            },
        )
    }
}

internal data class VpnSpec(
    val ipv6Prefix: Int,
    val meshPrefix: Int,
    val dnsPrefix: Int,
    val mtu: Int,
    val disallowedApplications: List<String>,
)
