package com.example.astro_journal

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class CameraAimOrientationCalculatorTest {
    @Test
    fun `world vectors produce cardinal vertical and diagonal aim`() {
        assertAim(east = 0.0, north = 1.0, up = 0.0, azimuth = 0.0, altitude = 0.0)
        assertAim(east = 1.0, north = 0.0, up = 0.0, azimuth = 90.0, altitude = 0.0)
        assertAim(east = 0.0, north = -1.0, up = 0.0, azimuth = 180.0, altitude = 0.0)
        assertAim(east = -1.0, north = 0.0, up = 0.0, azimuth = 270.0, altitude = 0.0)

        val zenith = CameraAimOrientationCalculator.fromWorldVector(0.0, 0.0, 1.0)
        assertNull(zenith.magneticAzimuthDegrees)
        assertEquals(90.0, zenith.altitudeDegrees, tolerance)
        val nadir = CameraAimOrientationCalculator.fromWorldVector(0.0, 0.0, -1.0)
        assertNull(nadir.magneticAzimuthDegrees)
        assertEquals(-90.0, nadir.altitudeDegrees, tolerance)

        assertSphericalAim(azimuth = 135.0, altitude = 45.0)
        assertSphericalAim(azimuth = 225.0, altitude = 30.0)
    }

    @Test
    fun `android matrices transform rear camera minus z into world aim`() {
        assertMatrixAim(
            matrix = floatArrayOf(
                1f, 0f, 0f,
                0f, 0f, -1f,
                0f, 1f, 0f,
            ),
            azimuth = 0.0,
            altitude = 0.0,
        )
        assertMatrixAim(
            matrix = floatArrayOf(
                0f, 0f, -1f,
                -1f, 0f, 0f,
                0f, 1f, 0f,
            ),
            azimuth = 90.0,
            altitude = 0.0,
        )
        assertMatrixAim(
            matrix = floatArrayOf(
                1f, 0f, 0f,
                0f, 0f, 1f,
                0f, 1f, 0f,
            ),
            azimuth = 180.0,
            altitude = 0.0,
        )
        assertMatrixAim(
            matrix = floatArrayOf(
                0f, 0f, 1f,
                1f, 0f, 0f,
                0f, 1f, 0f,
            ),
            azimuth = 270.0,
            altitude = 0.0,
        )
        assertMatrixAim(
            matrix = floatArrayOf(
                1f, 0f, 0f,
                0f, -sqrtHalf, -sqrtHalf,
                0f, sqrtHalf, -sqrtHalf,
            ),
            azimuth = 0.0,
            altitude = 45.0,
        )
    }

    @Test
    fun `portrait device top is distinct from rear camera optical axis`() {
        val northHorizontal = floatArrayOf(
            1f, 0f, 0f,
            0f, 0f, -1f,
            0f, 1f, 0f,
        )

        val cameraAim = CameraAimOrientationCalculator
            .fromDeviceToWorldRotationMatrix(northHorizontal)
        val deviceTop = CameraAimOrientationCalculator.fromWorldVector(
            east = northHorizontal[1].toDouble(),
            north = northHorizontal[4].toDouble(),
            up = northHorizontal[7].toDouble(),
        )

        assertEquals(0.0, cameraAim.magneticAzimuthDegrees!!, tolerance)
        assertEquals(0.0, cameraAim.altitudeDegrees, tolerance)
        assertNull(deviceTop.magneticAzimuthDegrees)
        assertEquals(90.0, deviceTop.altitudeDegrees, tolerance)
    }

    private fun assertSphericalAim(azimuth: Double, altitude: Double) {
        val azimuthRadians = Math.toRadians(azimuth)
        val altitudeRadians = Math.toRadians(altitude)
        val horizontal = cos(altitudeRadians)
        assertAim(
            east = horizontal * sin(azimuthRadians),
            north = horizontal * cos(azimuthRadians),
            up = sin(altitudeRadians),
            azimuth = azimuth,
            altitude = altitude,
        )
    }

    private fun assertAim(
        east: Double,
        north: Double,
        up: Double,
        azimuth: Double,
        altitude: Double,
    ) {
        val result = CameraAimOrientationCalculator.fromWorldVector(east, north, up)
        assertEquals(azimuth, result.magneticAzimuthDegrees!!, tolerance)
        assertEquals(altitude, result.altitudeDegrees, tolerance)
    }

    private fun assertMatrixAim(
        matrix: FloatArray,
        azimuth: Double,
        altitude: Double,
    ) {
        val result = CameraAimOrientationCalculator
            .fromDeviceToWorldRotationMatrix(matrix)
        assertEquals(azimuth, result.magneticAzimuthDegrees!!, matrixTolerance)
        assertEquals(altitude, result.altitudeDegrees, matrixTolerance)
    }

    private companion object {
        const val tolerance = 1e-9
        const val matrixTolerance = 1e-5
        const val sqrtHalf = 0.70710677f
    }
}
