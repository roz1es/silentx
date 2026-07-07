package ru.silentx.brenkschat_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Многие прошивки (MIUI, OnePlus и др.) рендерят приложения на 60 Гц,
        // пока приложение само не запросит режим дисплея с высокой частотой.
        // Выбираем режим с текущим разрешением и максимальным refresh rate —
        // на 120-герцовых экранах Flutter начинает получать vsync 120.
        requestMaxRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Локальные уведомления о сообщениях без Firebase: Dart шлёт сюда
        // show(id, title, body), когда приложение свёрнуто или чат не открыт.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brenks/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        ensureNotificationPermission()
                        result.success(true)
                    }
                    "show" -> {
                        showMessageNotification(
                            call.argument<Int>("id") ?: 0,
                            call.argument<String>("title") ?: "БренксЧат",
                            call.argument<String>("body") ?: "",
                        )
                        result.success(true)
                    }
                    "cancelAll" -> {
                        getSystemService(NotificationManager::class.java)?.cancelAll()
                        result.success(true)
                    }
                    "shareImage" -> {
                        val data = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "photo.jpg"
                        result.success(data != null && shareImage(data, name))
                    }
                    "saveImage" -> {
                        val data = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name")
                            ?: "brenks_${System.currentTimeMillis()}.jpg"
                        val mime = call.argument<String>("mime") ?: "image/jpeg"
                        result.success(data != null && saveImageToGallery(data, name, mime))
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url != null &&
                            (url.startsWith("http://") || url.startsWith("https://"))
                        ) {
                            try {
                                startActivity(
                                    android.content.Intent(
                                        android.content.Intent.ACTION_VIEW,
                                        android.net.Uri.parse(url),
                                    )
                                )
                            } catch (_: Throwable) {
                                // Нет браузера — молча пропускаем.
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun shareImage(data: ByteArray, name: String): Boolean {
        return try {
            val dir = java.io.File(cacheDir, "shared").apply { mkdirs() }
            val file = java.io.File(dir, name)
            file.outputStream().use { it.write(data) }
            val uri = androidx.core.content.FileProvider.getUriForFile(
                this, "$packageName.fileprovider", file,
            )
            val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(android.content.Intent.EXTRA_STREAM, uri)
                addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(android.content.Intent.createChooser(intent, "Поделиться"))
            true
        } catch (_: Throwable) {
            false
        }
    }

    // Сохранение картинки в галерею: MediaStore (API 29+) либо публичная
    // папка Pictures со сканированием (старые Android, включая BlueStacks).
    private fun saveImageToGallery(data: ByteArray, name: String, mime: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= 29) {
                val values = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, mime)
                    put(
                        android.provider.MediaStore.Images.Media.RELATIVE_PATH,
                        android.os.Environment.DIRECTORY_PICTURES + "/BrenksChat",
                    )
                }
                val uri = contentResolver.insert(
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: return false
                contentResolver.openOutputStream(uri)?.use { it.write(data) }
                    ?: return false
                true
            } else {
                if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(
                        arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        7002,
                    )
                    return false
                }
                val dir = java.io.File(
                    android.os.Environment.getExternalStoragePublicDirectory(
                        android.os.Environment.DIRECTORY_PICTURES,
                    ),
                    "BrenksChat",
                )
                dir.mkdirs()
                val file = java.io.File(dir, name)
                file.outputStream().use { it.write(data) }
                android.media.MediaScannerConnection.scanFile(
                    this, arrayOf(file.absolutePath), arrayOf(mime), null,
                )
                true
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 7001)
        }
    }

    private fun showMessageNotification(id: Int, title: String, body: String) {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "messages",
                    "Сообщения",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = "Новые сообщения" }
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, "messages")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        nm.notify(id, notification)
    }

    private fun requestMaxRefreshRate() {
        try {
            @Suppress("DEPRECATION")
            val display: Display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay) ?: return
            val current = display.mode
            var best: Display.Mode = current
            for (mode in display.supportedModes) {
                if (mode.physicalWidth == current.physicalWidth &&
                    mode.physicalHeight == current.physicalHeight &&
                    mode.refreshRate > best.refreshRate
                ) {
                    best = mode
                }
            }
            if (best.modeId != current.modeId) {
                val attrs = window.attributes
                attrs.preferredDisplayModeId = best.modeId
                window.attributes = attrs
            }
        } catch (_: Throwable) {
            // Не критично: остаёмся на частоте по умолчанию.
        }
    }
}
