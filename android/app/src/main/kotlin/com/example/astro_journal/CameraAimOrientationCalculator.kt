package com.example.astro_journal

import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.sqrt

internal data class CameraAimOrientation(
    val magneticAzimuthDegrees: Double?,
    val altitudeDegrees: Double,
)

/**
 * Converts the rear-camera optical axis into an East/North/Up direction.
 *
 * Android's rotation matrix transforms device coordinates to world ENU
 * coordinates. A built-in rear camera faces opposite the screen, along device
 * -Z, so its world vector is the negated third matrix column.
 */
internal object CameraAimOrientationCalculator {
    private const val HORIZONTAL_EPSILON = 1e-8

    fun fromDeviceToWorldRotationMatrix(matrix: FloatArray): CameraAimOrientation {
        require(matrix.size == 9) { "A 3x3 Android rotation matrix is required." }
        return fromWorldVector(
            east = -matrix[2].toDouble(),
            north = -matrix[5].toDouble(),
            up = -matrix[8].toDouble(),
        )
    }

    fun fromWorldVector(
        east: Double,
        north: Double,
        up: Double,
    ): CameraAimOrientation {
        require(east.isFinite() && north.isFinite() && up.isFinite()) {
            "Camera direction components must be finite."
        }
        val magnitude = sqrt(east * east + north * north + up * up)
        require(magnitude > 0.0) { "Camera direction must not be zero." }

        val normalizedEast = east / magnitude
        val normalizedNorth = north / magnitude
        val normalizedUp = up / magnitude
        val horizontalMagnitude = sqrt(
            normalizedEast * normalizedEast + normalizedNorth * normalizedNorth,
        )
        val magneticAzimuth = if (horizontalMagnitude < HORIZONTAL_EPSILON) {
            null
        } else {
            normalizeDegrees(Math.toDegrees(atan2(normalizedEast, normalizedNorth)))
        }
        return CameraAimOrientation(
            magneticAzimuthDegrees = magneticAzimuth,
            altitudeDegrees = Math.toDegrees(asin(normalizedUp.coerceIn(-1.0, 1.0))),
        )
    }

    private fun normalizeDegrees(value: Double): Double {
        val normalized = value % 360.0
        return if (normalized < 0) normalized + 360.0 else normalized
    }
}
