package com.neubetterpro.neu_better_pro

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import androidx.core.location.LocationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.Inet4Address
import java.net.Proxy
import java.net.URL
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection

@Suppress("DEPRECATION")
internal class CampusWifiChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "neu_better/campus_wifi")
    private val worker = Executors.newFixedThreadPool(2)
    private val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE)
        as WifiManager
    private val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE)
        as ConnectivityManager
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "currentSsid" -> readCurrentSsid(result)
                "ipv4Address" -> result.success(campusConnection(call.arguments as? String)?.ipv4)
                "requestLocationPermission" -> requestLocationPermission(result)
                "readGateway" -> readGateway(call.arguments as? String, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (hasLocationPermission()) {
            result.success(null)
            return
        }
        if (pending != null) {
            result.error("busy", "请先完成位置权限授权。", null)
            return
        }
        pending = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            LOCATION_REQUEST,
        )
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != LOCATION_REQUEST) return
        val result = pending ?: return
        pending = null
        if (hasLocationPermission()) {
            result.success(null)
        } else {
            result.error("location_required", "请允许精确位置权限，以识别当前 Wi-Fi。", null)
        }
    }

    private fun hasLocationPermission() =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun isLocationEnabled(): Boolean {
        val location = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return LocationManagerCompat.isLocationEnabled(location)
    }

    private fun readCurrentSsid(result: MethodChannel.Result) {
        if (!wifi.isWifiEnabled) {
            result.success(null)
            return
        }
        if (!hasLocationPermission()) {
            result.error("location_required", "请允许精确位置权限，以识别当前 Wi-Fi。", null)
            return
        }
        if (!isLocationEnabled()) {
            result.error("location_disabled", "请打开 Android 的系统位置服务，再刷新网络状态。", null)
            return
        }
        try {
            result.success(ssidOf(wifi.connectionInfo))
        } catch (_: SecurityException) {
            result.error("wifi_unavailable", "Android 无法读取 Wi-Fi 状态。", null)
        }
    }

    private fun ssidOf(info: WifiInfo?): String? =
        info?.ssid?.removeSurrounding("\"")?.takeUnless {
            it.isEmpty() || it == WifiManager.UNKNOWN_SSID
        }

    private fun normalizeSsid(ssid: String?) = ssid?.trim()?.lowercase()?.replace('－', '-')

    private data class CampusConnection(val network: Network, val ipv4: String)

    private fun campusConnection(expectedSsid: String? = null): CampusConnection? {
        if (!wifi.isWifiEnabled || !hasLocationPermission() || !isLocationEnabled()) return null
        val info = try {
            wifi.connectionInfo
        } catch (_: SecurityException) {
            return null
        } ?: return null
        val ssid = normalizeSsid(ssidOf(info))
        if (ssid !in CAMPUS_SSIDS || (expectedSsid != null && ssid != normalizeSsid(expectedSsid))) {
            return null
        }
        val address = info.ipAddress
        if (address == 0) return null
        // WifiInfo supplies the primary WLAN address. Match it to its Network
        // so an open captive portal can be reached even if mobile data is default.
        val raw = ByteArray(4) { index -> (address ushr (index * 8)).toByte() }
        for (network in connectivity.allNetworks) {
            val caps = connectivity.getNetworkCapabilities(network) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            val ipv4 = connectivity.getLinkProperties(network)?.linkAddresses
                ?.map { it.address }
                ?.filterIsInstance<Inet4Address>()
                ?.firstOrNull { !it.isLinkLocalAddress && it.address.contentEquals(raw) }
            val ip = ipv4?.hostAddress ?: continue
            return CampusConnection(network, ip)
        }
        return null
    }

    private fun readGateway(address: String?, result: MethodChannel.Result) {
        val url = try {
            address?.let { URL(it) }
        } catch (_: Exception) {
            null
        }
        if (url == null || url.protocol != "https" || url.host != GATEWAY ||
            url.port !in listOf(-1, 443) || url.userInfo != null || url.ref != null ||
            url.path !in GATEWAY_PATHS
        ) {
            result.error("invalid_gateway", "网关地址无效。", null)
            return
        }
        worker.execute {
            try {
                val route = campusConnection() ?: error("No campus Wi-Fi connection")
                val connection = route.network.openConnection(url, Proxy.NO_PROXY) as HttpsURLConnection
                try {
                    connection.connectTimeout = 6500
                    connection.readTimeout = 6500
                    connection.instanceFollowRedirects = false
                    connection.useCaches = false
                    val page = if (url.query?.split('&')?.contains("action=logout") == true) {
                        "srun_portal_success"
                    } else {
                        "srun_portal_sso"
                    }
                    connection.setRequestProperty("Referer", "https://$GATEWAY/$page?ac_id=1")
                    if (connection.responseCode !in 200..299) {
                        activity.runOnUiThread {
                            result.error("gateway_http_error", "学校网关返回了 HTTP 错误。", null)
                        }
                        return@execute
                    }
                    val body = connection.inputStream.use { stream ->
                        val buffer = ByteArray(4096)
                        val bytes = ByteArrayOutputStream()
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            check(bytes.size() + count <= MAX_RESPONSE_BYTES)
                            bytes.write(buffer, 0, count)
                        }
                        bytes.toString(Charsets.UTF_8.name())
                    }
                    activity.runOnUiThread { result.success(body) }
                } finally {
                    connection.disconnect()
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    result.error("gateway_unavailable", "无法访问学校网关。", null)
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.error("closed", "Wi-Fi 位置授权已结束。", null)
        pending = null
        worker.shutdownNow()
    }

    private companion object {
        const val GATEWAY = "ipgw.neu.edu.cn"
        const val LOCATION_REQUEST = 4202
        const val MAX_RESPONSE_BYTES = 64 * 1024
        val CAMPUS_SSIDS = setOf("neu", "neu-mobile", "neu2.4g")
        val GATEWAY_PATHS = setOf(
            "/v1/srun_portal_sso", "/cgi-bin/rad_user_info", "/cgi-bin/srun_portal",
        )
    }
}
