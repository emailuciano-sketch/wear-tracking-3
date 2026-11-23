package com.wear.tracking.v4

import android.content.Context
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkEventsSink: EventChannel.EventSink? = null
    @Volatile
    private var currentNetworkHandle: Long = -1L
    private val mainHandler = Handler(Looper.getMainLooper())

    private val networkLostRunnable = Runnable {
        if (!isFinishing && !isDestroyed) {
            networkEventsSink?.success("lost:$currentNetworkHandle")
        }
    }

    private val reapplyLandscapeRunnable = Runnable {
        if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            applySystemUiFlags(resources.configuration)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wear.tracking.v4/network"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                networkEventsSink = events
                registerNativeNetworkMonitor()
            }

            override fun onCancel(arguments: Any?) {
                unregisterNativeNetworkMonitor()
                networkEventsSink = null
            }
        })
    }

    private fun getNetworkHandleId(network: Network): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            network.networkHandle
        } else {
            network.hashCode().toLong()
        }
    }

    private fun registerNativeNetworkMonitor() {
        unregisterNativeNetworkMonitor()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val handle = getNetworkHandleId(network)
                val changed = currentNetworkHandle != -1L && currentNetworkHandle != handle
                currentNetworkHandle = handle
                mainHandler.post {
                    mainHandler.removeCallbacks(networkLostRunnable)
                    if (changed && !isFinishing && !isDestroyed) {
                        networkEventsSink?.success("available:$handle")
                    }
                }
            }

            override fun onLost(network: Network) {
                val handle = getNetworkHandleId(network)
                if (handle == currentNetworkHandle) {
                    mainHandler.post {
                        mainHandler.removeCallbacks(networkLostRunnable)
                        mainHandler.postDelayed(networkLostRunnable, 400)
                    }
                }
            }
        }
        networkCallback = callback
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                cm.registerDefaultNetworkCallback(callback)
            } else {
                val request = NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
                cm.registerNetworkCallback(request, callback)
            }
        } catch (_: Exception) {
        }
    }

    private fun unregisterNativeNetworkMonitor() {
        mainHandler.removeCallbacks(networkLostRunnable)
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val callback = networkCallback
        networkCallback = null
        if (cm != null && callback != null) {
            try {
                cm.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        val decorView = window.decorView
        @Suppress("DEPRECATION")
        decorView.setOnSystemUiVisibilityChangeListener { visibility ->
            if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE &&
                (visibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION) == 0
            ) {
                decorView.removeCallbacks(reapplyLandscapeRunnable)
                decorView.postDelayed(reapplyLandscapeRunnable, 150)
            }
        }
        applyOrientationFullscreen(resources.configuration)
    }

    private fun applySystemUiFlags(config: Configuration) {
        if (isFinishing || isDestroyed) return
        val decorView = window.decorView
        @Suppress("DEPRECATION")
        if (config.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                )
        } else {
            decorView.removeCallbacks(reapplyLandscapeRunnable)
            window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }

    private fun applyOrientationFullscreen(config: Configuration) {
        applySystemUiFlags(config)
        val decorView = window.decorView
        decorView.removeCallbacks(reapplyLandscapeRunnable)
        if (config.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            decorView.postDelayed(reapplyLandscapeRunnable, 200)
        }
    }

    override fun onResume() {
        super.onResume()
        applyOrientationFullscreen(resources.configuration)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyOrientationFullscreen(resources.configuration)
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyOrientationFullscreen(newConfig)
    }

    override fun onDestroy() {
        unregisterNativeNetworkMonitor()
        window.decorView.removeCallbacks(reapplyLandscapeRunnable)
        super.onDestroy()
    }
}
