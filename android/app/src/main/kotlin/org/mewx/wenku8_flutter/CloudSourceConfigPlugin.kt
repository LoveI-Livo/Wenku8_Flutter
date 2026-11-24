package org.mewx.wenku8_flutter

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** The cloud session vault is device-bound and excluded from Android backups. */
class CloudSourceConfigPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private var channel: MethodChannel? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val alias = "wenku8.cloud-sources.v1"
    private val credentialsAlias = "wenku8.account-credentials.v1"

    /**
     * 主保险箱绑定 AndroidKeyStore；系统升级或签名迁移极少数情况下会
     * 让旧密钥不可用。备用保险箱使用应用私有目录里的随机 AES 密钥，
     * 不写明文，也不读取设备标识；更新后仍能解密，随系统备份可迁移。
     */
    private fun fallbackKey(prefsName: String = "cloud_sources_fallback"): SecretKey {
        val prefs = context.getSharedPreferences(prefsName, 0)
        prefs.getString("key", null)?.let { encoded ->
            return SecretKeySpec(Base64.decode(encoded, Base64.NO_WRAP), "AES")
        }
        val material = ByteArray(32)
        SecureRandom().nextBytes(material)
        check(prefs.edit().putString("key", Base64.encodeToString(material, Base64.NO_WRAP)).commit())
        return SecretKeySpec(material, "AES")
    }

    private fun key(aliasName: String = alias): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey(aliasName, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(aliasName, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/cloud_sources").also { it.setMethodCallHandler(this) }
    }
    private fun decrypt(prefsName: String, secret: SecretKey): String? {
        val prefs = context.getSharedPreferences(prefsName, 0)
        val stored = prefs.getString("config", null) ?: return null
        val parts = stored.split(':'); require(parts.size == 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)).toString(Charsets.UTF_8)
    }

    private fun encrypt(prefsName: String, secret: SecretKey, text: String) {
        require(text.length <= 65536)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, secret)
        val data = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(cipher.doFinal(text.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        val prefs = context.getSharedPreferences(prefsName, 0)
        check(prefs.edit().putString("config", data).commit())
    }

    private fun remove(prefsName: String) {
        val prefs = context.getSharedPreferences(prefsName, 0)
        check(prefs.edit().remove("config").commit())
    }

    private fun readVault(
        secure: String,
        fallback: String,
        secretAlias: String,
    ): String? {
        var text: String? = runCatching { decrypt(secure, key(secretAlias)) }.getOrNull()
        if (text == null) {
            text = runCatching { decrypt(fallback, fallbackKey("${fallback}")) }.getOrNull()
        }
        if (text != null) {
            // 每次成功读取都刷新备用保险箱，升级后仍能直接恢复。
            runCatching { encrypt(fallback, fallbackKey("${fallback}"), text) }
        } else if (context.getSharedPreferences(secure, 0).contains("config") ||
            context.getSharedPreferences(fallback, 0).contains("config")) {
            throw IllegalStateException("secure vault unavailable")
        }
        return text
    }

    private fun writeVault(
        secure: String,
        fallback: String,
        secretAlias: String,
        text: String?,
    ) {
        if (text == null) {
            runCatching { remove(secure) }
            runCatching { remove(fallback) }
            return
        }
        var primary = false
        var backup = false
        runCatching { encrypt(secure, key(secretAlias), text) }.onSuccess { primary = true }
        runCatching { encrypt(fallback, fallbackKey("${fallback}"), text) }.onSuccess { backup = true }
        check(primary || backup)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read", "write", "readCredentials", "writeCredentials", "clearCredentials" -> Unit
            else -> { result.notImplemented(); return }
        }
        io.execute {
            try {
                val value = when (call.method) {
                    "read" -> readVault("cloud_sources_secure", "cloud_sources_fallback", alias)
                    "write" -> { writeVault("cloud_sources_secure", "cloud_sources_fallback", alias, call.arguments as? String); null }
                    "readCredentials" -> readVault("wenku_credentials_secure", "wenku_credentials_fallback", credentialsAlias)
                    "writeCredentials" -> { writeVault("wenku_credentials_secure", "wenku_credentials_fallback", credentialsAlias, call.arguments as? String); null }
                    "clearCredentials" -> { writeVault("wenku_credentials_secure", "wenku_credentials_fallback", credentialsAlias, null); null }
                    else -> null
                }
                main.post { result.success(value) }
            } catch (_: Exception) { main.post { result.error("secure_storage", "无法读取或保存本机账号保险箱，请重试", null) } }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null); channel = null; io.shutdown()
    }
}
