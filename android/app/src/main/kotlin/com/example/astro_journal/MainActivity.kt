package com.example.astro_journal

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val MAPS_CHANNEL = "com.example.astro_journal/maps"
        private const val SAF_CHANNEL = "com.example.astro_journal/saf_backup"
        private const val ORIENTATION_CHANNEL = "com.example.astro_journal/device_orientation"
        private const val TAG = "SafBackup"
    }

    private var pendingTreePickResult: MethodChannel.Result? = null
    private var pendingDocPickResult: MethodChannel.Result? = null
    private var orientationStreamHandler: DeviceOrientationStreamHandler? = null

    private val openTreeLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
            val flutterResult = pendingTreePickResult
            pendingTreePickResult = null
            if (flutterResult == null) return@registerForActivityResult

            if (activityResult.resultCode != Activity.RESULT_OK) {
                Log.i(TAG, "tree pick cancelled")
                flutterResult.success(null)
                return@registerForActivityResult
            }

            val uri = activityResult.data?.data
            if (uri == null) {
                Log.e(TAG, "tree pick returned null uri")
                flutterResult.error("NO_URI", "폴더 URI를 받지 못했습니다.", null)
                return@registerForActivityResult
            }

            val flags = activityResult.data?.flags ?: 0
            val takeFlags =
                flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
                Log.i(TAG, "persistable permission granted uri=$uri flags=$takeFlags")
            } catch (e: SecurityException) {
                // 일부 제공자는 persistable을 지원하지 않음 — 세션 내 쓰기만 가능
                Log.w(TAG, "takePersistableUriPermission failed: ${e.message}")
            }

            flutterResult.success(uri.toString())
        }

    private val openDocLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
            val flutterResult = pendingDocPickResult
            pendingDocPickResult = null
            if (flutterResult == null) return@registerForActivityResult

            if (activityResult.resultCode != Activity.RESULT_OK) {
                Log.i(TAG, "document pick cancelled")
                flutterResult.success(null)
                return@registerForActivityResult
            }

            val uri = activityResult.data?.data
            if (uri == null) {
                Log.e(TAG, "document pick returned null uri")
                flutterResult.error("NO_URI", "파일 URI를 받지 못했습니다.", null)
                return@registerForActivityResult
            }

            try {
                val flags = activityResult.data?.flags ?: 0
                val takeFlags = flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
                if (takeFlags != 0) {
                    try {
                        contentResolver.takePersistableUriPermission(uri, takeFlags)
                    } catch (_: SecurityException) {
                        // OPEN_DOCUMENT는 세션 권한이면 충분
                    }
                }
                val localPath = copyUriToCacheFile(uri)
                Log.i(TAG, "import zip copied to $localPath")
                flutterResult.success(localPath)
            } catch (e: Exception) {
                Log.e(TAG, "copyUriToCacheFile failed", e)
                flutterResult.error("COPY_FAILED", e.message, null)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        GoogleMapsApiKeyHolder.applyFromPreferences(applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val orientationHandler = DeviceOrientationStreamHandler(applicationContext)
        orientationStreamHandler = orientationHandler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ORIENTATION_CHANNEL)
            .setStreamHandler(orientationHandler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAPS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncGoogleMapsApiKey" -> {
                        val args = call.arguments as? Map<*, *>
                        val apiKey = args?.get("apiKey") as? String
                        GoogleMapsApiKeyHolder.sync(applicationContext, apiKey)
                        result.success(null)
                    }
                    "getMapsApiKeyStatus" -> {
                        result.success(GoogleMapsApiKeyHolder.readStatus(applicationContext))
                    }
                    "getManifestMapsApiKey" -> {
                        result.success(
                            GoogleMapsApiKeyHolder.readManifestApiKey(applicationContext),
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPersistableDirectory" -> pickPersistableDirectory(result)
                    "pickZipDocumentToCache" -> pickZipDocumentToCache(result)
                    "copyContentUriToCache" -> {
                        val uri = (call.arguments as? Map<*, *>)?.get("uri") as? String
                        if (uri.isNullOrBlank()) {
                            result.error("BAD_ARGS", "uri required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(copyUriToCacheFile(Uri.parse(uri)))
                        } catch (e: Exception) {
                            Log.e(TAG, "copyContentUriToCache failed", e)
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    "copyFileToTreeUri" -> {
                        val args = call.arguments as? Map<*, *>
                        val sourcePath = args?.get("sourcePath") as? String
                        val treeUri = args?.get("treeUri") as? String
                        val displayName = args?.get("displayName") as? String
                        if (sourcePath.isNullOrBlank() ||
                            treeUri.isNullOrBlank() ||
                            displayName.isNullOrBlank()
                        ) {
                            result.error(
                                "BAD_ARGS",
                                "sourcePath/treeUri/displayName required",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val outUri =
                                copyFileToTreeUri(sourcePath, treeUri, displayName)
                            result.success(outUri)
                        } catch (e: Exception) {
                            Log.e(TAG, "copyFileToTreeUri failed", e)
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }
                    "openDocumentUri" -> {
                        val uri = (call.arguments as? Map<*, *>)?.get("uri") as? String
                        if (uri.isNullOrBlank()) {
                            result.error("BAD_ARGS", "uri required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            openDocumentUri(uri)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "openDocumentUri failed", e)
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    "hasPersistablePermission" -> {
                        val uri = (call.arguments as? Map<*, *>)?.get("uri") as? String
                        if (uri.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(hasPersistablePermission(uri))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        orientationStreamHandler?.dispose()
        orientationStreamHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun pickPersistableDirectory(result: MethodChannel.Result) {
        if (pendingTreePickResult != null || pendingDocPickResult != null) {
            result.error("BUSY", "이미 파일/폴더 선택이 진행 중입니다.", null)
            return
        }
        pendingTreePickResult = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
            }
        Log.i(TAG, "launching ACTION_OPEN_DOCUMENT_TREE")
        openTreeLauncher.launch(intent)
    }

    private fun pickZipDocumentToCache(result: MethodChannel.Result) {
        if (pendingTreePickResult != null || pendingDocPickResult != null) {
            result.error("BUSY", "이미 파일/폴더 선택이 진행 중입니다.", null)
            return
        }
        pendingDocPickResult = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/zip",
                        "application/x-zip-compressed",
                        "application/octet-stream",
                    ),
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        Log.i(TAG, "launching ACTION_OPEN_DOCUMENT for zip")
        openDocLauncher.launch(intent)
    }

    private fun copyUriToCacheFile(uri: Uri): String {
        Log.i(TAG, "copyUriToCache start uri=$uri")
        val outFile = File(cacheDir, "import_backup_${System.currentTimeMillis()}.zip")
        val input =
            contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("InputStream 생성 실패: $uri")
        input.use { src ->
            outFile.outputStream().use { dst ->
                val buffer = ByteArray(1024 * 256)
                var total = 0L
                while (true) {
                    val read = src.read(buffer)
                    if (read <= 0) break
                    dst.write(buffer, 0, read)
                    total += read
                }
                dst.flush()
                Log.i(TAG, "copyUriToCache done bytes=$total path=${outFile.absolutePath}")
            }
        }
        if (!outFile.exists() || outFile.length() <= 0L) {
            throw IllegalStateException("복사된 ZIP이 비어 있습니다.")
        }
        return outFile.absolutePath
    }

    private fun copyFileToTreeUri(
        sourcePath: String,
        treeUriString: String,
        displayName: String,
    ): String {
        Log.i(TAG, "copy start source=$sourcePath tree=$treeUriString name=$displayName")

        val source = File(sourcePath)
        if (!source.exists() || !source.isFile) {
            throw IllegalStateException("소스 ZIP이 없습니다: $sourcePath")
        }

        val treeUri = Uri.parse(treeUriString)
        val hasPerm = hasPersistablePermission(treeUriString)
        Log.i(TAG, "permission check persisted=$hasPerm uri=$treeUri")

        val tree =
            DocumentFile.fromTreeUri(this, treeUri)
                ?: throw IllegalStateException("DocumentFile.fromTreeUri 실패: $treeUri")

        if (!tree.canWrite()) {
            throw IllegalStateException("선택한 폴더에 쓰기 권한이 없습니다.")
        }

        tree.findFile(displayName)?.let { existing ->
            Log.i(TAG, "deleting existing ${existing.uri}")
            existing.delete()
        }

        val created =
            tree.createFile("application/zip", displayName)
                ?: throw IllegalStateException("DocumentFile.createFile 실패")
        Log.i(TAG, "file created uri=${created.uri}")

        val outStream =
            contentResolver.openOutputStream(created.uri, "w")
                ?: throw IllegalStateException("OutputStream 생성 실패: ${created.uri}")
        Log.i(TAG, "OutputStream opened")

        outStream.use { output ->
            FileInputStream(source).use { input ->
                val buffer = ByteArray(1024 * 256)
                var total = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    output.write(buffer, 0, read)
                    total += read
                }
                output.flush()
                Log.i(TAG, "write complete bytes=$total")
            }
        }

        Log.i(TAG, "save done uri=${created.uri}")
        return created.uri.toString()
    }

    private fun openDocumentUri(uriString: String) {
        val uri = Uri.parse(uriString)
        val intent =
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/zip")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        startActivity(Intent.createChooser(intent, "백업 파일 열기"))
    }

    private fun hasPersistablePermission(uriString: String): Boolean {
        val target = Uri.parse(uriString)
        return contentResolver.persistedUriPermissions.any { perm ->
            val permUri = perm.uri
            if (permUri == target) return@any true
            val targetStr = target.toString()
            val permStr = permUri.toString()
            targetStr.startsWith(permStr) || permStr.startsWith(targetStr)
        }
    }
}
