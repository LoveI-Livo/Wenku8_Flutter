package org.mewx.wenku8_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Source builds attach local platform capabilities only. */
internal fun attachWenkuEnginePlugins(engine: FlutterEngine) {
    if (!engine.plugins.has(ReadingWidgetsPlugin::class.java)) engine.plugins.add(ReadingWidgetsPlugin())
    if (!engine.plugins.has(AppHapticsPlugin::class.java)) engine.plugins.add(AppHapticsPlugin())
    if (!engine.plugins.has(MonetPlugin::class.java)) engine.plugins.add(MonetPlugin())
    if (!engine.plugins.has(WenkuHostPlugin::class.java)) engine.plugins.add(WenkuHostPlugin())
    if (!engine.plugins.has(SystemSpeechPlugin::class.java)) engine.plugins.add(SystemSpeechPlugin())
    if (!engine.plugins.has(AppUpdatePlugin::class.java)) engine.plugins.add(AppUpdatePlugin())
    if (!engine.plugins.has(CloudSourceConfigPlugin::class.java)) engine.plugins.add(CloudSourceConfigPlugin())
    if (!engine.plugins.has(ReaderControlsPlugin::class.java)) engine.plugins.add(ReaderControlsPlugin())
    if (!engine.plugins.has(NetworkStatusPlugin::class.java)) engine.plugins.add(NetworkStatusPlugin())
    if (!engine.plugins.has(FrameRatePlugin::class.java)) engine.plugins.add(FrameRatePlugin())
}

class WenkuHostPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener, PluginRegistry.NewIntentListener {
    private var toolsChannel: MethodChannel? = null
    private var tools: LocalTools? = null
    private var documents: BookDocuments? = null
    private var bookImports: BookDocumentImportSession<Uri>? = null
    private var bookOpens: BookOpenRequests? = null
    private var documentsChannel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var lanChannel: MethodChannel? = null
    private var lanPending: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val resolver = binding.applicationContext.contentResolver
        bookImports = BookDocumentImportSession(File(binding.applicationContext.noBackupFilesDir, "book-import-staging")) { uri, target, max ->
            copySelectedBookDocument(resolver, uri, target, max)
        }
        bookOpens = BookOpenRequests(binding.applicationContext)
        toolsChannel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/local_tools").also {
            it.setMethodCallHandler { call, result ->
                val attached = tools
                if (attached != null) attached.onMethodCall(call, result)
                else result.error("NO_ACTIVITY", "This action needs the app page", null)
            }
        }
        lanChannel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/lan_permission").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "requestLocalNetwork") requestLanPermission(result)
                else result.notImplemented()
            }
        }
        documentsChannel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/book_documents").also {
            it.setMethodCallHandler { call, result ->
                val attached = documents
                if (attached != null) attached.onMethodCall(call, result)
                else result.error("NO_ACTIVITY", "请在文库页面执行文件操作", null)
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        bookImports?.close()
        bookImports = null
        bookOpens = null
        toolsChannel?.setMethodCallHandler(null)
        documentsChannel?.setMethodCallHandler(null)
        lanChannel?.setMethodCallHandler(null)
        lanChannel = null
        lanPending?.success(false)
        lanPending = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        tools = LocalTools(binding.activity)
        documents = BookDocuments(binding.activity, checkNotNull(bookImports), checkNotNull(bookOpens))
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
        binding.addOnNewIntentListener(this)
        onNewIntent(binding.activity.intent)
        documentsChannel?.invokeMethod("bookOpenAvailable", null)
    }
    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        lanPending?.success(false)
        lanPending = null
        tools?.close(); tools = null
        documents?.close(); documents = null
    }
    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onNewIntent(intent: Intent): Boolean {
        if (bookOpens?.offer(intent) != true) return false
        activityBinding?.activity?.let { activity ->
            activity.intent = Intent(activity.intent).apply { action = Intent.ACTION_MAIN; data = null; type = null }
        }
        documentsChannel?.invokeMethod("bookOpenAvailable", null)
        return true
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        (tools?.onActivityResult(requestCode, resultCode, data) ?: false) ||
            (documents?.onActivityResult(requestCode, resultCode, data) ?: false)
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == lanPermissionRequest) {
            val pending = lanPending
            lanPending = null
            pending?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            return true
        }
        return documents?.onRequestPermissionsResult(requestCode) ?: false
    }

    private fun requestLanPermission(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "请在应用页面请求本地网络权限", null)
            return
        }
        val permission = when {
            android.os.Build.VERSION.SDK_INT >= 37 -> "android.permission.ACCESS_LOCAL_NETWORK"
            android.os.Build.VERSION.SDK_INT >= 33 -> "android.permission.NEARBY_WIFI_DEVICES"
            else -> null
        }
        if (permission == null || activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (lanPending != null) {
            result.success(false)
            return
        }
        lanPending = result
        activity.requestPermissions(arrayOf(permission), lanPermissionRequest)
    }

    private companion object {
        const val lanPermissionRequest = 4901
    }
}
