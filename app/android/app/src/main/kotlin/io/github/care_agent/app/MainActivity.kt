package io.github.care_agent.app

import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.care_agent.app.automation.CareAutomationPlugin
import io.github.care_agent.app.ecosystem.CareEcosystemPlugin
import io.github.care_agent.app.proactive.CareProactivePlugin
import io.github.care_agent.app.runtime.CareRuntimeController
import io.github.care_agent.app.runtime.CareRuntimePlugin
import io.github.care_agent.app.safety.CareSafetyGatePlugin
import io.github.care_agent.app.share.CareSharePlugin
import io.github.care_agent.app.vault.CareBiometricVaultPlugin
import io.github.care_agent.app.workspace.CareWorkspacePlugin

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        }
        CareSharePlugin.handleIntent(applicationContext, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        CareSharePlugin.handleIntent(applicationContext, intent)
    }

    override fun onStart() {
        super.onStart()
        CareRuntimeController.get(applicationContext).onAppForegrounded()
    }

    override fun onStop() {
        CareRuntimeController.get(applicationContext).onAppBackgrounded()
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(CareRuntimePlugin())
        flutterEngine.plugins.add(CareSafetyGatePlugin())
        flutterEngine.plugins.add(CareProactivePlugin())
        flutterEngine.plugins.add(CareEcosystemPlugin())
        flutterEngine.plugins.add(CareAutomationPlugin())
        flutterEngine.plugins.add(CareBiometricVaultPlugin())
        flutterEngine.plugins.add(CareWorkspacePlugin())
        flutterEngine.plugins.add(CareSharePlugin())
    }
}
