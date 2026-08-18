package com.example.astro_journal

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import kotlin.math.asin
import kotlin.math.atan2

/**
 * Emits the rear camera optical-axis orientation for the portrait-only
 * Horizon Scan. Android device +X is screen-right, +Y is screen-up and the
 * rear camera looks along -Z. Values are deliberately kept independent of
 * Flutter UI and database concerns.
 */
class DeviceOrientationStreamHandler(
    context: Context,
) : EventChannel.StreamHandler,
    SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var eventSink: EventChannel.EventSink? = null
    private var activeSensor: Sensor? = null
    private var sensorAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var declinationDegrees: Float? = null
    private val rotationMatrix = FloatArray(9)

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        stop()
        eventSink = events
        declinationDegrees = readDeclination(arguments)
        activeSensor =
            sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                ?: sensorManager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        val sensor = activeSensor
        if (sensor == null) {
            events.error(
                "SENSOR_UNAVAILABLE",
                "이 기기에서는 자동 시야 측정을 사용할 수 없습니다.",
                null,
            )
            eventSink = null
            return
        }
        val registered = sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        if (!registered) {
            events.error(
                "SENSOR_UNAVAILABLE",
                "방향 센서를 시작할 수 없습니다.",
                null,
            )
            eventSink = null
            activeSensor = null
        }
    }

    override fun onCancel(arguments: Any?) {
        stop()
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor != activeSensor || event.values.isEmpty()) return
        sensorAccuracy = event.accuracy
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

        // SensorManager's matrix transforms device coordinates to East/North/Up.
        // The rear-facing camera forward vector is device -Z.
        val east = -rotationMatrix[2].toDouble()
        val north = -rotationMatrix[5].toDouble()
        val up = -rotationMatrix[8].toDouble()
        if (east * east + north * north < 0.0001) return

        val magneticAzimuth = Math.toDegrees(atan2(east, north))
        val trueNorthCorrection = declinationDegrees?.toDouble() ?: 0.0
        val azimuth = normalizeDegrees(magneticAzimuth + trueNorthCorrection)
        val pitch = Math.toDegrees(asin(up.coerceIn(-1.0, 1.0)))

        // Roll is the world-up projection on the screen right/up axes.
        val roll = Math.toDegrees(
            atan2(rotationMatrix[6].toDouble(), rotationMatrix[7].toDouble()),
        )
        eventSink?.success(
            mapOf(
                "timestampNanos" to event.timestamp,
                "azimuth" to azimuth,
                "pitch" to pitch,
                "roll" to roll,
                "accuracy" to accuracyName(sensorAccuracy),
                "trueNorthApplied" to (declinationDegrees != null),
                "sensorType" to event.sensor.type,
            ),
        )
    }

    override fun onAccuracyChanged(
        sensor: Sensor?,
        accuracy: Int,
    ) {
        if (sensor == activeSensor) sensorAccuracy = accuracy
    }

    fun dispose() {
        stop()
    }

    private fun stop() {
        sensorManager.unregisterListener(this)
        activeSensor = null
        eventSink = null
        sensorAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    }

    private fun readDeclination(arguments: Any?): Float? {
        val values = arguments as? Map<*, *> ?: return null
        val latitude = (values["latitude"] as? Number)?.toDouble() ?: return null
        val longitude = (values["longitude"] as? Number)?.toDouble() ?: return null
        if (!latitude.isFinite() || !longitude.isFinite()) return null
        return GeomagneticField(
            latitude.toFloat(),
            longitude.toFloat(),
            0f,
            System.currentTimeMillis(),
        ).declination
    }

    private fun accuracyName(accuracy: Int): String =
        when (accuracy) {
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> "good"
            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> "medium"
            SensorManager.SENSOR_STATUS_ACCURACY_LOW,
            SensorManager.SENSOR_STATUS_UNRELIABLE,
            -> "low"
            else -> "unknown"
        }

    private fun normalizeDegrees(value: Double): Double {
        val normalized = value % 360.0
        return if (normalized < 0) normalized + 360.0 else normalized
    }
}
