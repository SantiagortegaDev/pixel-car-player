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

    /** WifiManager ints are little-endian. */
    fun intToIp(ip: Int): String =
        "${ip and 0xff}.${ip shr 8 and 0xff}.${ip shr 16 and 0xff}.${ip shr 24 and 0xff}"
}
