import Testing
@testable import SunStatusCore

@Suite("Sun arc projection")
struct SunArcProjectionTests {
    @Test("Top-down camera eye sits directly above the center")
    func topDownEyePosition() {
        let eye = SunArcProjection.eyePosition(
            for: SunArcCamera(headingDegrees: 120, pitchDegrees: 0, centerDistanceMeters: 500)
        )

        #expect(eye.x == 0)
        #expect(eye.y == 500)
        #expect(eye.z == 0)
    }

    @Test("Pitched north-facing camera eye sits south of the center")
    func northFacingPitchedEyePosition() {
        let eye = SunArcProjection.eyePosition(
            for: SunArcCamera(headingDegrees: 0, pitchDegrees: 60, centerDistanceMeters: 100)
        )

        #expect(abs(eye.x) < 0.000_001)
        #expect(abs(eye.y - 50) < 0.000_001)
        #expect(abs(eye.z + 86.602_540) < 0.000_001)
    }

    @Test("Ground point intersects itself")
    func groundPointIntersectsItself() {
        let point = SunVector3(x: 40, y: 0, z: 80)
        let intersection = SunArcProjection.groundIntersection(
            of: point,
            camera: SunArcCamera(headingDegrees: 42, pitchDegrees: 58, centerDistanceMeters: 850)
        )

        #expect(intersection != nil)
        #expect(abs((intersection?.x ?? 0) - point.x) < 0.000_001)
        #expect(abs((intersection?.y ?? 0) - point.y) < 0.000_001)
        #expect(abs((intersection?.z ?? 0) - point.z) < 0.000_001)
    }

    @Test("Elevated point projects past itself along the eye ray")
    func elevatedPointProjectsPastItself() {
        let camera = SunArcCamera(headingDegrees: 0, pitchDegrees: 60, centerDistanceMeters: 100)
        let point = SunVector3(x: 10, y: 25, z: 0)
        let intersection = SunArcProjection.groundIntersection(of: point, camera: camera)

        #expect(intersection != nil)
        #expect((intersection?.x ?? 0) > point.x)
        #expect((intersection?.y ?? -1) == 0)
        #expect((intersection?.z ?? 0) > point.z)
    }

    @Test("Point at or above eye height is hidden")
    func pointAtEyeHeightIsHidden() {
        let camera = SunArcCamera(headingDegrees: 0, pitchDegrees: 60, centerDistanceMeters: 100)
        let eye = SunArcProjection.eyePosition(for: camera)
        let intersection = SunArcProjection.groundIntersection(
            of: SunVector3(x: 0, y: eye.y, z: 0),
            camera: camera
        )

        #expect(intersection == nil)
    }
}
