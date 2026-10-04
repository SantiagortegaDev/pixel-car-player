package com.santiagortega.pixelcarplayer

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Redes (ConnectivityManager + LinkProperties) para el enlace v2: en Android 10+ un Wi-Fi sin
 * internet no es la red por defecto, así que los sockets del enlace se enlazan a cada [Network]
 * Wi-Fi con `Network.bindSocket`.
 */
object WifiNets {

    /** Una red IPv4. [network] es null para interfaces sin objeto Network (el hotspot propio). */
    data class NetInfo(
        val network: Network?,
        val iface: String?,
        val ip: String?,
        val prefix: Int,
        val gateway: String?,
        val broadcast: String?,
        val hasInternet: Boolean,
        val isDefault: Boolean,
        val isWifi: Boolean,
        val isHotspot: Boolean,
    ) {
        /** Clave estable para diagnósticos y para cachear sockets por red. */
        val key: String get() = "${iface ?: "?"}/${network?.toString() ?: "-"}"

        fun toMap(): Map<String, Any?> = mapOf(
            "name" to (iface ?: network?.toString()),
            "iface" to iface,
            "ip" to ip,
            "prefix" to prefix,
            "gateway" to gateway,
            "broadcast" to broadcast,
            "hasInternet" to hasInternet,
            "isDefault" to isDefault,
            "isWifi" to isWifi,
            "isHotspot" to isHotspot,
        )
    }

    private val AP_IFACE = Regex("""^(ap\d*|wlan1|swlan\d*|softap\d*)$""")

    // ------------------------------------------------------------------ pure helpers

    /** Dirección de broadcast IPv4 de [ip]/[prefix] (null si no es IPv4 válida o prefijo fuera de 0..32). */
    fun broadcastAddress(ip: String, prefix: Int): String? {
        val b = ipv4Bytes(ip) ?: return null
        if (prefix !in 0..32) return null
        val addr = toInt(b)
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        return fromInt(addr or mask.inv())
    }

    /** true si [ip] cae en la subred [netIp]/[prefix]. */
    fun sameSubnet(ip: String, netIp: String, prefix: Int): Boolean {
        val a = ipv4Bytes(ip) ?: return false
        val b = ipv4Bytes(netIp) ?: return false
        if (prefix !in 0..32) return false
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        return (toInt(a) and mask) == (toInt(b) and mask)
    }

    fun ipv4Bytes(ip: String): ByteArray? {
        val parts = ip.trim().split('.')
        if (parts.size != 4) return null
        val out = ByteArray(4)
        for (i in 0..3) {
            val n = parts[i].toIntOrNull() ?: return null
            if (n !in 0..255) return null
            out[i] = n.toByte()
        }
        return out
    }

    private fun toInt(b: ByteArray): Int =
        (b[0].toInt() and 0xff shl 24) or (b[1].toInt() and 0xff shl 16) or
            (b[2].toInt() and 0xff shl 8) or (b[3].toInt() and 0xff)

    private fun fromInt(v: Int): String = "${v ushr 24 and 0xff}.${v ushr 16 and 0xff}.${v ushr 8 and 0xff}.${v and 0xff}"

    // ------------------------------------------------------------------ ConnectivityManager

    private fun cm(ctx: Context) = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    fun info(cm: ConnectivityManager, n: Network, active: Network?): NetInfo? {
        val lp: LinkProperties = try {
            cm.getLinkProperties(n)
        } catch (_: Exception) {
            null
        } ?: return null
        val caps: NetworkCapabilities? = try {
            cm.getNetworkCapabilities(n)
        } catch (_: Exception) {
            null
        }
        val la = lp.linkAddresses.firstOrNull { it.address is Inet4Address }
        val ip = la?.address?.hostAddress
        val prefix = la?.prefixLength ?: 0
        val gw = try {
            lp.routes.firstOrNull { r ->
                val g = r.gateway
                r.isDefaultRoute && g is Inet4Address && !g.isAnyLocalAddress
            }?.gateway?.hostAddress
        } catch (_: Exception) {
            null
        }
        val internet = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        return NetInfo(
            network = n,
            iface = lp.interfaceName,
            ip = ip,
            prefix = prefix,
            gateway = gw,
            broadcast = ip?.let { broadcastAddress(it, prefix) },
            hasInternet = internet,
            isDefault = active != null && active == n,
            isWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true,
            isHotspot = false,
        )
    }

    /** Todas las redes conocidas (allNetworks ∪ [extra], p. ej. las del NetworkCallback). */
    @Suppress("DEPRECATION")
    fun networks(ctx: Context, extra: Collection<Network> = emptyList()): List<NetInfo> {
        val cm = cm(ctx) ?: return emptyList()
        return try {
            val active = cm.activeNetwork
            val all = LinkedHashSet<Network>()
            all += cm.allNetworks
            all += extra
            all.mapNotNull { info(cm, it, active) }
        } catch (e: Exception) {
            Log.w(TAG, "network enumeration failed", e)
            emptyList()
        }
    }

    /** Redes Wi-Fi con IPv4 (con o sin internet). */
    fun wifiNetworks(ctx: Context, extra: Collection<Network> = emptyList()): List<NetInfo> =
        networks(ctx, extra).filter { it.isWifi && it.ip != null }

    /** Interfaces de hotspot (ap0, wlan1, swlan0…) que no tienen objeto Network. */
    fun hotspotInterfaces(known: Set<String>): List<NetInfo> {
        val out = mutableListOf<NetInfo>()
        try {
            for (nif in NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()) {
                val name = nif.name ?: continue
                if (name in known || !AP_IFACE.matches(name)) continue
                if (!runCatching { nif.isUp }.getOrDefault(false)) continue
                val ia = nif.interfaceAddresses.firstOrNull { it.address is Inet4Address } ?: continue
                val ip = ia.address.hostAddress ?: continue
                val prefix = ia.networkPrefixLength.toInt()
                out += NetInfo(
                    network = null, iface = name, ip = ip, prefix = prefix, gateway = null,
                    broadcast = ia.broadcast?.hostAddress ?: broadcastAddress(ip, prefix),
                    hasInternet = false, isDefault = false, isWifi = true, isHotspot = true,
                )
            }
        } catch (e: Exception) {
            Log.d(TAG, "interface enumeration failed: ${e.message}")
        }
        return out
    }

    /** `getWifiNetworks`: todas las redes + interfaces de hotspot. */
    fun describe(ctx: Context, extra: Collection<Network> = emptyList()): List<Map<String, Any?>> {
        val nets = networks(ctx, extra)
        val known = nets.mapNotNull { it.iface }.toSet()
        return (nets + hotspotInterfaces(known)).map { it.toMap() }
    }
}
