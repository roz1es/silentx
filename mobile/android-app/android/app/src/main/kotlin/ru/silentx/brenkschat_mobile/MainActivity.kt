package ru.silentx.brenkschat_mobile

import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Многие прошивки (MIUI, OnePlus и др.) рендерят приложения на 60 Гц,
        // пока приложение само не запросит режим дисплея с высокой частотой.
        // Выбираем режим с текущим разрешением и максимальным refresh rate —
        // на 120-герцовых экранах Flutter начинает получать vsync 120.
        requestMaxRefreshRate()
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
