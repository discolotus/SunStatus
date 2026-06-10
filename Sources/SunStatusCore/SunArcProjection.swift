import Foundation

public struct SunArcCamera: Equatable, Sendable {
    public let headingDegrees: Double
    public let pitchDegrees: Double
    public let centerDistanceMeters: Double

    public init(headingDegrees: Double, pitchDegrees: Double, centerDistanceMeters: Double) {
        self.headingDegrees = headingDegrees
        self.pitchDegrees = pitchDegrees
        self.centerDistanceMeters = centerDistanceMeters
    }
}

public enum SunArcProjection {
    public static func eyePosition(for camera: SunArcCamera) -> SunVector3 {
        let heading = degreesToRadians(camera.headingDegrees)
        let pitch = degreesToRadians(camera.pitchDegrees)
        let horizontalDistance = camera.centerDistanceMeters * sin(pitch)

        return SunVector3(
            x: -sin(heading) * horizontalDistance,
            y: camera.centerDistanceMeters * cos(pitch),
            z: -cos(heading) * horizontalDistance
        )
    }

    public static func groundIntersection(of point: SunVector3, camera: SunArcCamera) -> SunVector3? {
        let eye = eyePosition(for: camera)
        guard eye.y > 0, point.y < eye.y else {
            return nil
        }

        let t = eye.y / (eye.y - point.y)
        return SunVector3(
            x: eye.x + (t * (point.x - eye.x)),
            y: 0,
            z: eye.z + (t * (point.z - eye.z))
        )
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
