package com.wingmanbefree.wingman_app.fips

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import com.wingmanbefree.wingman_app.MainActivity
import com.wingmanbefree.wingman_app.R
import org.json.JSONObject
import java.util.concurrent.Executors

class FipsVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    private var tun: ParcelFileDescriptor? = null
    @Volatile private var stopped = false

    override fun onCreate() {
        super.onCreate()
        current = this
        startForeground(NOTIFICATION_ID, notification("Starting embedded FIPS mesh…"))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            worker.execute { shutdown() }
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, notification("Starting embedded FIPS mesh…"))
        worker.execute {
            stopped = false
            runCatching { establishAndRun() }
                .onFailure { failClosed() }
        }
        return START_NOT_STICKY
    }

    @Synchronized
    private fun establishAndRun() {
        if (stopped || tun != null) return
        val metadata = JSONObject(FipsNative.nativeInspect())
        val ipv6 = metadata.optString("ipv6")
        if (ipv6.isBlank()) {
            failClosed()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            failClosed()
            return
        }
        val underlyingNetwork = selectUnderlyingNetwork()
        if (underlyingNetwork == null) {
            failClosed()
            return
        }

        val spec = FipsPlatformContract.vpnSpec
        // Deliberately no addDisallowedApplication(packageName): WM-App's own
        // WebView must enter this VPN. FIPS UDP sockets are protected below.
        val descriptor = Builder()
            .setSession("Wingman FIPS mesh")
            .addAddress(ipv6, spec.ipv6Prefix)
            .addAddress(FipsPlatformContract.VPN_ADDRESS, spec.dnsPrefix)
            .addRoute(FipsPlatformContract.MESH_ROUTE, spec.meshPrefix)
            .addRoute(FipsPlatformContract.DNS_ADDRESS, spec.dnsPrefix)
            .addDnsServer(FipsPlatformContract.DNS_ADDRESS)
            .setUnderlyingNetworks(arrayOf(underlyingNetwork))
            .setMtu(spec.mtu)
            .setBlocking(true)
            .establish()
        if (descriptor == null) {
            failClosed()
            return
        }
        tun = descriptor

        val started = JSONObject(FipsNative.nativeStartNode())
        val sockets = started.optJSONArray("transportSockets")
        if (!started.optBoolean("ok") || sockets == null || sockets.length() == 0) {
            failClosed()
            return
        }
        for (index in 0 until sockets.length()) {
            val fd = sockets.getJSONObject(index).getInt("fd")
            if (!protect(fd)) {
                failClosed()
                return
            }
        }

        val rustFd = ParcelFileDescriptor.dup(descriptor.fileDescriptor).detachFd()
        val running = JSONObject(
            FipsNative.nativeRunNode(rustFd, underlyingNetwork.networkHandle),
        )
        if (running.optString("state") != "running") {
            failClosed()
            return
        }
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification("Routing fd00::/8 and .fips DNS"))
    }

    private fun selectUnderlyingNetwork(): Network? {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val active = connectivity.activeNetwork
        val candidates = buildList {
            if (active != null) add(active)
            addAll(connectivity.allNetworks.filterNot { it == active })
        }
        return candidates.firstOrNull { network ->
            val capabilities = connectivity.getNetworkCapabilities(network) ?: return@firstOrNull false
            FipsPlatformContract.isEligibleUnderlyingNetwork(
                hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
                isVpn = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
            )
        }
    }

    private fun failClosed() {
        shutdown()
    }

    @Synchronized
    private fun resetForStart() {
        FipsNative.nativeStop()
        tun?.close()
        tun = null
        stopped = false
    }

    @Synchronized
    private fun shutdown() {
        if (stopped) return
        stopped = true
        FipsNative.nativeStop()
        tun?.close()
        tun = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        worker.execute { shutdown() }
        super.onRevoke()
    }

    override fun onDestroy() {
        if (current === this) current = null
        if (!stopped && !worker.isShutdown) {
            worker.execute { shutdown() }
        }
        worker.shutdown()
        super.onDestroy()
    }

    private fun notification(detail: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "FIPS mesh VPN", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle("Wingman FIPS VPN active")
            .setContentText(detail)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val ACTION_STOP = "com.wingmanbefree.wingman_app.fips.STOP"
        private const val CHANNEL_ID = "wmapp_fips_vpn"
        private const val NOTIFICATION_ID = 2121
        @Volatile private var current: FipsVpnService? = null

        fun start(context: Context) {
            val intent = Intent(context, FipsVpnService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val service = current
            if (service != null) {
                service.shutdown()
            } else {
                FipsNative.nativeStop()
                context.stopService(Intent(context, FipsVpnService::class.java))
            }
        }

        fun resetForStart(context: Context) {
            val service = current
            if (service != null) {
                service.resetForStart()
            } else {
                FipsNative.nativeStop()
                context.stopService(Intent(context, FipsVpnService::class.java))
            }
        }
    }
}
