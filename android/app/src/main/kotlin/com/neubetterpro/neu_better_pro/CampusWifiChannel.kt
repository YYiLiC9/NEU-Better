package com.neubetterpro.neu_better_pro

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
    private val main = Handler(Looper.getMainLooper())
    private val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE)
        as WifiManager
    private val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE)
        as ConnectivityManager
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "currentSsid" -> result.success(currentSsid())
                "ipv4Address" -> result.success(campusConnection()?.ipv4)
                "connect" -> begin(result)
                "readGateway" -> readGateway(call.arguments as? String, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun begin(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "请先完成系统 Wi-Fi 连接。", null)
            return
        }
        pending = result
        if (hasLocationPermission()) {
            openOrContinue()
        } else {
            activity.requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                LOCATION_REQUEST,
            )
        }
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != LOCATION_REQUEST || pending == null) return
        if (hasLocationPermission()) {
            openOrContinue()
        } else {
            fail("location_required", "请允许精确位置权限，Android 才能确认已连接 NEU Wi-Fi。")
        }
    }

    private fun openOrContinue() {
        val location = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (!LocationManagerCompat.isLocationEnabled(location)) {
            fail("location_disabled", "请打开 Android 的系统位置服务，以确认已连接 NEU Wi-Fi。")
            return
        }
        if (currentSsid() == SSID) {
            complete()
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && wifi.isWifiEnabled) {
            val add = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).apply {
                putParcelableArrayListExtra(
                    Settings.EXTRA_WIFI_NETWORK_LIST,
                    arrayListOf(WifiNetworkSuggestion.Builder().setSsid(SSID).build()),
                )
            }
            try {
                activity.startActivityForResult(add, SAVE_WIFI_REQUEST)
                return
            } catch (_: ActivityNotFoundException) {
                // OEMs can omit the saved-network screen.
            } catch (_: SecurityException) {
                // The system Wi-Fi screen remains available.
            }
        }
        openWifiSettings()
    }

    private fun openWifiSettings() {
        try {
            activity.startActivityForResult(Intent(Settings.ACTION_WIFI_SETTINGS), WIFI_SETTINGS_REQUEST)
        } catch (_: Exception) {
            fail("settings_unavailable", "请从 Android 系统设置连接 NEU Wi-Fi 后重试。")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (pending == null) return
        when (requestCode) {
            SAVE_WIFI_REQUEST -> {
                if (currentSsid() == SSID) {
                    complete()
                    return
                }
                if (resultCode != Activity.RESULT_OK) {
                    fail("cancelled", "未确认加入 NEU Wi-Fi。")
                    return
                }
                val added = data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST)
                    ?.firstOrNull() == Settings.ADD_WIFI_RESULT_SUCCESS
                if (added) {
                    main.postDelayed({
                        if (pending != null) {
                            if (currentSsid() == SSID) complete() else openWifiSettings()
                        }
                    }, 2000)
                } else {
                    openWifiSettings()
                }
            }
            WIFI_SETTINGS_REQUEST -> complete()
        }
    }

    private fun hasLocationPermission() =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun currentSsid(): String? {
        if (!hasLocationPermission() || !wifi.isWifiEnabled) return null
        return try {
            wifi.connectionInfo?.ssid?.removeSurrounding("\"")?.takeUnless {
                it.isEmpty() || it == WifiManager.UNKNOWN_SSID
            }
        } catch (_: SecurityException) {
            null
        }
    }

    private data class CampusConnection(val network: Network, val ipv4: String)

    private fun campusConnection(): CampusConnection? {
        if (currentSsid() != SSID) return null
        val address = wifi.connectionInfo?.ipAddress ?: return null
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
                val route = campusConnection() ?: error("No NEU Wi-Fi connection")
                val connection = route.network.openConnection(url, Proxy.NO_PROXY) as HttpsURLConnection
                try {
                    connection.connectTimeout = 6500
                    connection.readTimeout = 6500
                    connection.instanceFollowRedirects = false
                    connection.useCaches = false
                    check(connection.responseCode in 200..299)
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

    private fun complete() {
        val result = pending
        pending = null
        result?.success(null)
    }

    private fun fail(code: String, message: String) {
        val result = pending
        pending = null
        result?.error(code, message, null)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        main.removeCallbacksAndMessages(null)
        fail("closed", "Wi-Fi 连接操作已结束。")
        worker.shutdownNow()
    }

    private companion object {
        const val SSID = "NEU"
        const val GATEWAY = "ipgw.neu.edu.cn"
        const val LOCATION_REQUEST = 4202
        const val SAVE_WIFI_REQUEST = 4203
        const val WIFI_SETTINGS_REQUEST = 4204
        const val MAX_RESPONSE_BYTES = 64 * 1024
        val GATEWAY_PATHS = setOf(
            "/cgi-bin/rad_user_info", "/cgi-bin/get_challenge", "/cgi-bin/srun_portal",
        )
    }
}
