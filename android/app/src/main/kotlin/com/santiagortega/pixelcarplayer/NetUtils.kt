package com.santiagortega.pixelcarplayer

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface

object NetUtils {

    private fun upInterfaces(): List<NetworkInterface> = try {
        NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
            .filter { runCatching { it.isUp && !it.isLoopback }.getOrDefault(false) }
    } catch (e: Exception) {
        Log.w(TAG, "NetworkInterface enumeration failed", e)
        emptyList()
    }

    /** Non-loopback IPv4 addresses of all up interfaces. */
    fun localIps(): List<String> = upInterfaces()
        .flatMap { it.inetAddresses.toList() }
        .filterIsInstance<Inet4Address>()
        .filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }
        .mapNotNull { it.hostAddress }
        .distinct()

    /** Broadcast addresses of every up IPv4 interface, plus 255.255.255.255. */
    fun broadcastAddresses(): List<InetAddress> {
        val out = LinkedHashSet<InetAddress>()
        for (nif in upInterfaces()) {
            try {
                nif.interfaceAddresses.forEach { ia ->
                    val bc = ia.broadcast
                    if (ia.address is Inet4Address && bc != null) out += bc
                }
            } catch (_: Exception) {
            }
        }
        try {
            out += InetAddress.getByName("255.255.255.255")
        } catch (_: Exception) {
        }
        return out.toList()
    }

    /**
     * IPv4 gateway of the Wi-Fi network (the phone when the car is on its hotspot), or null.
     */
    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    fun gatewayIp(context: Context): String? {
        try {
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val gw = wifi?.dhcpInfo?.gateway ?: 0
            if (gw != 0) return intToIp(gw)
        } catch (e: Exception) {
            Log.w(TAG, "dhcpInfo failed", e)
        }
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return null
            val networks = cm.allNetworks.sortedByDescending { n ->
                // Prefer Wi-Fi networks.
                cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
            for (n in networks) {
                val lp = cm.getLinkProperties(n) ?: continue
                for (route in lp.routes) {
                    val g = route.gateway
                    if (route.isDefaultRoute && g is Inet4Address && !g.isAnyLocalAddress) {
                        return g.hostAddress
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "LinkProperties gateway lookup failed", e)
        }
        return null
    }

    // ------------------------------------------------------------------ neighbours (hotspot clients)

    private val IPV4 = Regex("""^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$""")

    private fun isIpv4(s: String) = IPV4.matchEntire(s)?.groupValues?.drop(1)?.all { it.toInt() in 0..255 } == true

    /** `/proc/net/arp`: complete entries (flags 0x2) with a real MAC. */
    fun parseArp(text: String): List<String> = text.lineSequence()
        .drop(1) // header
        .mapNotNull { line ->
            val f = line.trim().split(Regex("\\s+"))
            if (f.size < 4) return@mapNotNull null
            val ip = f[0]
            val flags = f[2].removePrefix("0x").toIntOrNull(16) ?: 0
            val mac = f[3]
            ip.takeIf { isIpv4(it) && flags and 0x2 != 0 && mac != "00:00:00:00:00:00" }
        }
        .distinct()
        .toList()

    /** `ip neigh` output: IPv4 entries in REACHABLE / STALE / DELAY / PROBE / PERMANENT state. */
    fun parseIpNeigh(text: String): List<String> {
        val good = setOf("REACHABLE", "STALE", "DELAY", "PROBE", "PERMANENT")
        return text.lineSequence()
            .mapNotNull { line ->
                val f = line.trim().split(Regex("\\s+"))
                val ip = f.firstOrNull() ?: return@mapNotNull null
                ip.takeIf { isIpv4(it) && f.contains("lladdr") && f.lastOrNull() in good }
            }
            .distinct()
            .toList()
    }

    /**
     * IPv4 neighbours from the ARP table. Note: apps targeting API 29+ are denied /proc/net/arp on
     * Android 10+, and `ip neigh` (netlink) on Android 11+; then this returns an empty list.
     */
    fun neighborIps(): List<String> {
        val out = LinkedHashSet<String>()
        try {
            out += parseArp(java.io.File("/proc/net/arp").readText())
        } catch (e: Exception) {
            Log.d(TAG, "/proc/net/arp unreadable: ${e.message}")
        }
        try {
            val p = ProcessBuilder("ip", "-4", "neigh", "show").redirectErrorStream(true).start()
            val text = p.inputStream.bufferedReader().use { it.readText() }
            p.destroy() // output fully read; Process.waitFor(timeout) needs API 26
            out += parseIpNeigh(text)
        } catch (e: Exception) {
            Log.d(TAG, "ip neigh failed: ${e.message}")
        }
        return out.toList()
    }

    /** WifiManager ints are little-endian. */
    fun intToIp(ip: Int): String =
        "${ip and 0xff}.${ip shr 8 and 0xff}.${ip shr 16 and 0xff}.${ip shr 24 and 0xff}"
}
