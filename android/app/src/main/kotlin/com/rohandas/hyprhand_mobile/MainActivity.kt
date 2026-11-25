package com.rohandas.hyprhand_mobile

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private var captureUp = false
    private var captureDown = false
    private var capturePower = false
    private var resumed = false
    private var pausedAt = 0L
    private var leftByUser = false

    /** Apps never receive KEYCODE_POWER, so a press is inferred from the screen
     *  going off while we were in front (the Dart side prevents timeouts). */
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.action == Intent.ACTION_USER_PRESENT) { setStandby(false); return }
            if (i.action == Intent.ACTION_SCREEN_ON) {
                if (standby) channel?.invokeMethod("screenOn", null)
                return
            }
            if (capturePower) setStandby(true)
            val inFront = resumed || SystemClock.elapsedRealtime() - pausedAt < 1500
            if (!capturePower || leftByUser || !inFront) return
            channel?.invokeMethod("powerKey", null)
            ui.postDelayed({ wake() }, 200)
        }
    }

    @Suppress("DEPRECATION")
    private fun wake() {
        if (!capturePower) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        try {
            pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "hyprhand:power",
            ).acquire(2000)
        } catch (e: SecurityException) { /* the chain still ran; screen stays off */ }
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        leftByUser = false
        // If the phone turns out not to have locked (delayed auto-lock), open up
        // again, but only once the keyguard has had ample time to appear.
        ui.removeCallbacks(recheck)
        if (standby) ui.postDelayed(recheck, 2500)
    }

    // ── standby: nothing but the assigned buttons works until unlock ──

    private val keyguard by lazy { getSystemService(KEYGUARD_SERVICE) as KeyguardManager }
    private var standby = false
    private var cover: View? = null
    private var touchY = 0f
    private val recheck = Runnable {
        if (resumed && !keyguard.isKeyguardLocked) setStandby(false)
    }

    private fun setStandby(on: Boolean) {
        ui.removeCallbacks(recheck)
        // Only on entering standby: on later power presses Flutter is already
        // showing the standby face and would never ask for the cover to go.
        if (on && !standby && cover == null) {
            // Hides the last deck frame until Flutter has drawn the standby face.
            cover = View(this).apply { setBackgroundColor(0xFF000000.toInt()) }
            val full = ViewGroup.LayoutParams.MATCH_PARENT
            addContentView(cover, ViewGroup.LayoutParams(full, full))
        }
        if (!on) uncover()
        if (standby == on) return
        standby = on
        channel?.invokeMethod("locked", on)
    }

    private fun uncover() {
        cover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        cover = null
    }

    private fun requestUnlock() {
        keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
            override fun onDismissSucceeded() = setStandby(false)
            override fun onDismissError() { if (!keyguard.isKeyguardLocked) setStandby(false) }
        })
    }

    /** Touches never reach the app while locked; a swipe up asks to unlock. */
    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        if (!standby) return super.dispatchTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> touchY = e.y
            MotionEvent.ACTION_UP ->
                if (touchY - e.y > 80 * resources.displayMetrics.density) requestUnlock()
        }
        return true
    }

    override fun dispatchGenericMotionEvent(e: MotionEvent): Boolean =
        standby || super.dispatchGenericMotionEvent(e)

    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        if (!standby) return super.dispatchKeyEvent(e)
        if (captures(e.keyCode)) {
            return if (e.action == KeyEvent.ACTION_DOWN) onKeyDown(e.keyCode, e) else true
        }
        // Uncaptured volume keys keep their system meaning; all else is dropped.
        val volume = e.keyCode == KeyEvent.KEYCODE_VOLUME_UP || e.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        return if (volume) super.dispatchKeyEvent(e) else true
    }
    override fun onPause() {
        resumed = false
        pausedAt = SystemClock.elapsedRealtime()
        super.onPause()
    }
    override fun onUserLeaveHint() { leftByUser = true; super.onUserLeaveHint() }

    private var pickResult: MethodChannel.Result? = null
    private var pendingShare: Intent? = null
    private var pendingShortcut: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        standby = keyguard.isKeyguardLocked
        super.onCreate(savedInstanceState)
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF).apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_ON)
        })
        // A recreated activity replays its launch intent; don't share twice.
        if (savedInstanceState == null) accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        accept(intent)
        if (pendingShare != null) channel?.invokeMethod("shareReady", null)
        pendingShortcut?.let { channel?.invokeMethod("shortcut", it); pendingShortcut = null }
    }

    private fun accept(i: Intent?) {
        if (i == null || (i.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        when (i.action) {
            Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> pendingShare = i
            ACTION_OPEN -> pendingShortcut = i.getStringExtra("page")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hyprhand/native").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        val f = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        if (call.arguments == true) window.addFlags(f) else window.clearFlags(f)
                        result.success(null)
                    }
                    "captureKeys" -> {
                        captureUp = call.argument<Boolean>("up") == true
                        captureDown = call.argument<Boolean>("down") == true
                        capturePower = call.argument<Boolean>("power") == true
                        setShowWhenLocked(capturePower)
                        result.success(null)
                    }
                    "isLocked" -> result.success(standby)
                    "requestUnlock" -> { requestUnlock(); result.success(null) }
                    "standbyShown" -> { ui.postDelayed({ uncover() }, 120); result.success(null) }
                    "battery" -> result.success(battery())
                    "takeShortcut" -> { result.success(pendingShortcut); pendingShortcut = null }
                    "takeShare" -> takeShare(result)
                    "pickFiles" -> pickFiles(result)
                    "saveImage" -> saveImage(call.argument("bytes")!!, call.argument("name")!!, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Hardware volume keys drive the rig while the deck is open.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (captures(keyCode)) {
            val dir = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) 1 else -1
            channel?.invokeMethod("volumeKey", mapOf("dir" to dir, "held" to (event.repeatCount > 0)))
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (captures(keyCode)) return true
        return super.onKeyUp(keyCode, event)
    }

    private fun captures(keyCode: Int) =
        (captureUp && keyCode == KeyEvent.KEYCODE_VOLUME_UP) ||
            (captureDown && keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)

    private fun battery(): Map<String, Any> {
        val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
        return mapOf(
            "level" to bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
            "charging" to bm.isCharging,
        )
    }

    // ── files in ──

    private fun pickFiles(result: MethodChannel.Result) {
        if (pickResult != null) { result.success(emptyList<Any>()); return }
        pickResult = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            @Suppress("DEPRECATION") startActivityForResult(i, PICK)
        } catch (e: Exception) {
            pickResult = null
            result.error("pick", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK) return
        val r = pickResult ?: return
        pickResult = null
        val uris = if (resultCode == Activity.RESULT_OK) clipUris(data) else emptyList()
        copyAll(uris) { r.success(it) }
    }

    private fun clipUris(i: Intent?): List<Uri> {
        val clip = i?.clipData
        if (clip != null) return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
        return listOfNotNull(i?.data)
    }

    private fun takeShare(result: MethodChannel.Result) {
        val i = pendingShare ?: return result.success(null)
        pendingShare = null
        @Suppress("DEPRECATION")
        val uris: List<Uri> = if (i.action == Intent.ACTION_SEND_MULTIPLE)
            i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        else listOfNotNull(i.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
        val text = i.getStringExtra(Intent.EXTRA_TEXT)
        copyAll(uris) { result.success(mapOf("text" to text, "files" to it)) }
    }

    /** Copies content URIs into our cache. Only content:// is accepted, so another
     *  app can't hand us a file:// path into our own private storage. */
    private fun copyAll(uris: List<Uri>, done: (List<Map<String, Any>>) -> Unit) {
        io.execute {
            val root = File(cacheDir, "outbox").apply { mkdirs() }
            val cutoff = System.currentTimeMillis() - 3_600_000
            root.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.deleteRecursively() }
            val out = uris
                .filter { it.scheme == "content" && it.authority?.startsWith(packageName) != true }
                .mapNotNull { u ->
                    try {
                        val name = File(displayName(u)).name.ifBlank { "file" }
                        val dir = File(root, System.nanoTime().toString()).apply { mkdirs() }
                        val f = File(dir, "data")
                        contentResolver.openInputStream(u)!!.use { s -> f.outputStream().use { s.copyTo(it) } }
                        mapOf("path" to f.path, "name" to name, "size" to f.length())
                    } catch (e: Exception) { null }
                }
            ui.post { done(out) }
        }
    }

    private fun displayName(u: Uri): String {
        contentResolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.let { n -> return n }
        }
        return u.lastPathSegment ?: "file"
    }

    // ── files out ──

    private fun saveImage(bytes: ByteArray, name: String, result: MethodChannel.Result) {
        io.execute {
            val ok = try {
                val v = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/hyprhand")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v)!!
                try {
                    contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
                    v.clear(); v.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, v, null, null)
                    true
                } catch (e: Exception) { contentResolver.delete(uri, null, null); false }
            } catch (e: Exception) { false }
            ui.post { result.success(ok) }
        }
    }

    override fun onDestroy() {
        unregisterReceiver(screenOff)
        channel?.setMethodCallHandler(null)
        channel = null
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val PICK = 7001
        private const val ACTION_OPEN = "com.rohandas.hyprhand_mobile.OPEN"
    }
}
