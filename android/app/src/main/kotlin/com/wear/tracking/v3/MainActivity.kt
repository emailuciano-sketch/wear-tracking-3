package com.wear.tracking.v3

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    private val reapplyLandscapeRunnable = Runnable {
        if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            applySystemUiFlags(resources.configuration)
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
        window.decorView.removeCallbacks(reapplyLandscapeRunnable)
        super.onDestroy()
    }
}
