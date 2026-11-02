package com.samlytics.attenlume

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Method channel for the Android photo picker [P1-58, FR-PHO-05, ADR-074].
 *
 * Uses the system photo picker (ActivityResultContracts.PickMultipleVisualMedia)
 * without requiring READ_MEDIA_IMAGES permission.
 *
 * For each picked photo:
 * - Streams original bytes to cache.
 * - For HEIC/HEIF photos (API 28+), decodes via ImageDecoder and transcodes
 *   to JPEG (quality 95) with EXIF dates preserved via ExifInterface so
 *   subsequent processing and non-HEIC platforms (Windows/Linux) can display them.
 * - Extracts original capture time natively via ExifInterface (TAG_DATETIME_ORIGINAL
 *   and OffsetTimeOriginal) and returns an ISO-8601 UTC timestamp in takenIso.
 */
object PhotoPickerChannel : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "com.samlytics.attenlume/photo_picker"
    const val MAX_ITEMS = 50

    private var channel: MethodChannel? = null
    private var activity: MainActivity? = null
    private var pendingResult: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()

    fun attach(messenger: BinaryMessenger, mainActivity: MainActivity) {
        activity = mainActivity
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
        // Do NOT resolve pendingResult as cancelled here: if the activity is being
        // recreated (e.g. low memory while picker is open), the pending call remains
        // awaiting the picker result to be delivered once re-attached [P1-58 item 2].
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> {
                val act = activity
                if (act == null) {
                    result.error("UNAVAILABLE", "Activity not attached", null)
                    return
                }
                pendingResult?.let {
                    try {
                        it.success(emptyList<Map<String, Any>>())
                    } catch (_: Exception) {}
                }
                pendingResult = result
                val max = (call.argument<Int>("maxItems") ?: MAX_ITEMS).coerceIn(1, MAX_ITEMS)
                try {
                    act.launchPhotoPicker(max)
                } catch (e: Exception) {
                    pendingResult?.error("LAUNCH_FAILED", e.message, null)
                    pendingResult = null
                }
            }
            "cleanUp" -> {
                val act = activity
                if (act != null) {
                    executor.execute {
                        cleanPickedDir(act)
                        act.runOnUiThread {
                            result.success(true)
                        }
                    }
                } else {
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onPickerResult(uris: List<Uri>) {
        val res = pendingResult ?: return
        pendingResult = null
        val act = activity ?: run {
            res.success(emptyList<Map<String, Any>>())
            return
        }
        if (uris.isEmpty()) {
            res.success(emptyList<Map<String, Any>>())
            return
        }

        executor.execute {
            val list = mutableListOf<Map<String, Any>>()
            val cacheDir = File(act.cacheDir, "picked").apply { mkdirs() }
            val resolver = act.contentResolver

            for (uri in uris) {
                var displayName: String? = null
                try {
                    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val col = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (col >= 0) {
                                displayName = cursor.getString(col)
                            }
                        }
                    }
                } catch (_: Exception) {}

                val mime = resolver.getType(uri)
                val ext = when {
                    displayName != null && displayName!!.contains(".") -> {
                        val sub = displayName!!.substringAfterLast('.', "")
                        if (sub.isNotEmpty()) ".$sub" else ".jpg"
                    }
                    else -> when (mime) {
                        "image/png" -> ".png"
                        "image/webp" -> ".webp"
                        "image/heic" -> ".heic"
                        "image/heif" -> ".heif"
                        else -> ".jpg"
                    }
                }

                val safeName = displayName ?: "${UUID.randomUUID()}$ext"
                val rawFile = File(cacheDir, "${UUID.randomUUID()}$ext")

                var bytesWritten = 0L
                try {
                    resolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(rawFile).use { output ->
                            bytesWritten = input.copyTo(output)
                        }
                    }
                } catch (_: Exception) {}

                if (!rawFile.exists() || bytesWritten <= 0) {
                    continue
                }

                // Handle HEIC/HEIF transcoding and native EXIF capture timestamp extraction
                val (processedFile, processedName) = transcodeHeicIfNeeded(rawFile, mime, safeName, cacheDir)
                val takenIso = extractNativeExifTime(processedFile)

                list.add(
                    mapOf(
                        "path" to processedFile.absolutePath,
                        "name" to processedName,
                        "bytes" to processedFile.length(),
                        "takenIso" to (takenIso ?: "")
                    )
                )
            }

            act.runOnUiThread {
                res.success(list)
            }
        }
    }

    /**
     * Transcodes HEIC/HEIF to high-quality JPEG (quality 95) on Android 9+ (API 28+).
     * Preserves EXIF DateTimeOriginal on the converted JPEG file [P1-58 item 1].
     */
    private fun transcodeHeicIfNeeded(
        file: File,
        mimeType: String?,
        safeName: String,
        cacheDir: File
    ): Pair<File, String> {
        val lowerName = safeName.lowercase(Locale.ROOT)
        val isHeic = lowerName.endsWith(".heic") || lowerName.endsWith(".heif") ||
                mimeType == "image/heic" || mimeType == "image/heif"

        if (!isHeic) {
            return Pair(file, safeName)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                // Read original EXIF tags before transcoding
                val origExif = try { ExifInterface(file.absolutePath) } catch (_: Exception) { null }
                val origDate = origExif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                val origOffset = origExif?.getAttribute("OffsetTimeOriginal")

                val source = ImageDecoder.createSource(file)
                val bitmap = ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.isMutableRequired = false
                }

                val jpegFile = File(cacheDir, "${UUID.randomUUID()}.jpg")
                FileOutputStream(jpegFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
                }
                bitmap.recycle()

                // Preserve original EXIF date on the transcoded JPEG
                if (origDate != null) {
                    try {
                        val newExif = ExifInterface(jpegFile.absolutePath)
                        newExif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, origDate)
                        if (origOffset != null) {
                            newExif.setAttribute("OffsetTimeOriginal", origOffset)
                        }
                        newExif.saveAttributes()
                    } catch (_: Exception) {}
                }

                // Delete the temporary HEIC raw file
                file.delete()

                val jpegName = if (safeName.contains('.')) {
                    safeName.substringBeforeLast('.') + ".jpg"
                } else {
                    "$safeName.jpg"
                }
                return Pair(jpegFile, jpegName)
            } catch (_: Exception) {
                // If decoding fails, fall back gracefully to the original file
            }
        }
        return Pair(file, safeName)
    }

    /**
     * Extracts capture timestamp natively via ExifInterface [P1-58 item 1].
     * Returns an ISO-8601 UTC string (e.g. "2026-11-04T09:40:00.000Z") or null.
     */
    fun extractNativeExifTime(file: File): String? {
        try {
            val exif = ExifInterface(file.absolutePath)
            val dateStr = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: return null
            val offsetStr = exif.getAttribute("OffsetTimeOriginal")
            return parseExifToIsoUtc(dateStr, offsetStr)
        } catch (_: Exception) {
            return null
        }
    }

    /**
     * Parses "YYYY:MM:DD HH:MM:SS" with optional "+/-HH:MM" offset into ISO-8601 UTC.
     */
    fun parseExifToIsoUtc(exifDateTime: String, offset: String?): String? {
        val regex = Regex("""^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})""")
        val match = regex.find(exifDateTime.trim()) ?: return null
        val year = match.groupValues[1].toInt()
        if (year == 0) return null
        val month = match.groupValues[2].toInt()
        val day = match.groupValues[3].toInt()
        val hour = match.groupValues[4].toInt()
        val min = match.groupValues[5].toInt()
        val sec = match.groupValues[6].toInt()

        if (offset != null) {
            val offsetRegex = Regex("""^([+-])(\d{2}):(\d{2})$""")
            val oMatch = offsetRegex.find(offset.trim())
            if (oMatch != null) {
                val sign = if (oMatch.groupValues[1] == "-") -1 else 1
                val offHours = oMatch.groupValues[2].toInt()
                val offMins = oMatch.groupValues[3].toInt()
                val totalOffsetMinutes = sign * (offHours * 60 + offMins)

                val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
                    set(year, month - 1, day, hour, min, sec)
                    set(Calendar.MILLISECOND, 0)
                    add(Calendar.MINUTE, -totalOffsetMinutes)
                }
                return String.format(
                    Locale.US,
                    "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                    cal.get(Calendar.YEAR),
                    cal.get(Calendar.MONTH) + 1,
                    cal.get(Calendar.DAY_OF_MONTH),
                    cal.get(Calendar.HOUR_OF_DAY),
                    cal.get(Calendar.MINUTE),
                    cal.get(Calendar.SECOND)
                )
            }
        }

        // Without offset: interpret as device local time and convert to UTC
        val localCal = Calendar.getInstance().apply {
            set(year, month - 1, day, hour, min, sec)
            set(Calendar.MILLISECOND, 0)
        }
        val utcCal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            timeInMillis = localCal.timeInMillis
        }
        return String.format(
            Locale.US,
            "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
            utcCal.get(Calendar.YEAR),
            utcCal.get(Calendar.MONTH) + 1,
            utcCal.get(Calendar.DAY_OF_MONTH),
            utcCal.get(Calendar.HOUR_OF_DAY),
            utcCal.get(Calendar.MINUTE),
            utcCal.get(Calendar.SECOND)
        )
    }

    fun cleanPickedDir(context: Context) {
        try {
            val cacheDir = File(context.cacheDir, "picked")
            if (cacheDir.exists() && cacheDir.isDirectory) {
                cacheDir.listFiles()?.forEach { it.delete() }
            }
        } catch (_: Exception) {}
    }
}
