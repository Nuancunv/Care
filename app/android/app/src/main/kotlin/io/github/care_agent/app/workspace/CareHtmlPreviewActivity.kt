package io.github.care_agent.app.workspace

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Lightweight native Android WebView activity for rendering HTML files created
 * inside a Care workspace (offline-safe: JS enabled for interactive pages, local
 * file/content access strictly disabled so rendered HTML cannot read app data).
 */
class CareHtmlPreviewActivity : Activity() {
    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val titleText = intent.getStringExtra(EXTRA_TITLE) ?: "网页预览"
        val html = intent.getStringExtra(EXTRA_HTML) ?: ""

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#F3F8FF"))
            fitsSystemWindows = true
        }

        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.WHITE)
            val padH = dp(16)
            val padV = dp(10)
            setPadding(padH, padV, padH, padV)
            elevation = dp(2).toFloat()
        }

        val titleView = TextView(this).apply {
            text = titleText
            setTextColor(Color.parseColor("#142238"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeBtn = Button(this).apply {
            text = "关闭"
            setTextColor(Color.parseColor("#2E86F7"))
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { finish() }
        }

        topBar.addView(titleView)
        topBar.addView(closeBtn)

        val wv = WebView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                useWideViewPort = true
                loadWithOverviewMode = true
                builtInZoomControls = true
                displayZoomControls = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            }
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): Boolean {
                    val scheme = request?.url?.scheme?.lowercase() ?: ""
                    // Keep navigation inside safe preview; ignore file:// or custom intent schemes.
                    return scheme != "http" && scheme != "https" && scheme != "about"
                }
            }
            loadDataWithBaseURL(
                "https://care.local/",
                html,
                "text/html",
                "UTF-8",
                null,
            )
        }
        webView = wv

        root.addView(topBar)
        root.addView(wv)
        setContentView(root)
    }

    override fun onDestroy() {
        webView?.destroy()
        webView = null
        super.onDestroy()
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()

    companion object {
        const val EXTRA_TITLE = "care.html.title"
        const val EXTRA_HTML = "care.html.content"
    }
}
