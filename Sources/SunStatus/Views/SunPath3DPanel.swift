import AppKit
import SceneKit
import SwiftUI
import SunStatusCore

struct SunPath3DPanel: View {
    let status: DaylightStatus

    @State private var previewProgress = 0.5

    private var pathSamples: [SunPathSample3D] {
        SunPathGeometry.samples(from: status.arcPoints)
    }

    private var selectedSample: SunPathSample3D {
        SunPathGeometry.sample(at: previewProgress, arcPoints: status.arcPoints, fallback: status.solar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                SunPath3DSceneView(pathSamples: pathSamples, selectedSample: selectedSample)
                    .frame(height: 200)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                compassOverlay
            }

            angleReadouts

            VStack(spacing: 4) {
                Slider(value: $previewProgress, in: 0...1) {
                    Text("Preview time")
                }

                HStack {
                    Text(timeText(status.solar.sunrise))
                    Spacer()
                    Text(timeText(selectedSample.date))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeText(status.solar.sunset))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            previewProgress = status.solar.daylightProgress ?? 0.5
        }
        .onChange(of: status.solar.date) { _, _ in
            previewProgress = status.solar.daylightProgress ?? previewProgress
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var compassOverlay: some View {
        VStack {
            Text("N")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Text("W")
                Spacer()
                Text("E")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            Text("S")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private var angleReadouts: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                AngleTile(title: "Elevation", value: degreesText(selectedSample.elevationDegrees), symbolName: "arrow.up.right")
                AngleTile(title: "Azimuth", value: bearingText(selectedSample.azimuthDegrees), symbolName: "location.north.line")
            }

            GridRow {
                AngleTile(title: "Shadow", value: shadowText, symbolName: "arrow.down.left")
                AngleTile(title: "Mode", value: selectedSample.elevationDegrees > 0 ? "Day path" : "Below horizon", symbolName: "cube.transparent")
            }
        }
    }

    private var shadowText: String {
        guard let bearing = selectedSample.shadowBearingDegrees else {
            return "-"
        }

        return bearingText(bearing)
    }

    private var accessibilitySummary: String {
        "3D sun path, elevation \(degreesText(selectedSample.elevationDegrees)), azimuth \(bearingText(selectedSample.azimuthDegrees)), shadow \(shadowText)"
    }

    private func degreesText(_ degrees: Double) -> String {
        "\(Int(degrees.rounded())) deg"
    }

    private func bearingText(_ degrees: Double) -> String {
        "\(cardinalDirection(for: degrees)) \(Int(normalizedDegrees(degrees).rounded())) deg"
    }

    private func cardinalDirection(for degrees: Double) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = normalizedDegrees(degrees)
        let index = Int((normalized / 45).rounded()) % labels.count
        return labels[index]
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.timeZone = status.timezone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct AngleTile: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minWidth: 160, minHeight: 50)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SunPath3DSceneView: NSViewRepresentable {
    let pathSamples: [SunPathSample3D]
    let selectedSample: SunPathSample3D

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.scene = SunPathSceneFactory.scene(pathSamples: pathSamples, selectedSample: selectedSample)
    }
}

private enum SunPathSceneFactory {
    static func scene(pathSamples: [SunPathSample3D], selectedSample: SunPathSample3D) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        scene.rootNode.addChildNode(cameraNode())
        scene.rootNode.addChildNode(ambientLightNode())
        scene.rootNode.addChildNode(keyLightNode())
        scene.rootNode.addChildNode(gridNode())
        scene.rootNode.addChildNode(horizonNode())
        scene.rootNode.addChildNode(pathNode(samples: pathSamples))
        scene.rootNode.addChildNode(pathMarkersNode(samples: pathSamples))
        scene.rootNode.addChildNode(currentSunNode(sample: selectedSample))
        scene.rootNode.addChildNode(currentVectorNode(sample: selectedSample))
        scene.rootNode.addChildNode(shadowNode(sample: selectedSample))
        scene.rootNode.addChildNode(referencePostNode())

        return scene
    }

    private static func cameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 2.05
        camera.zNear = 0.1
        camera.zFar = 100

        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(0, 2.45, 3.75)
        node.look(at: SCNVector3(0, 0.35, 0))
        return node
    }

    private static func ambientLightNode() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.color = NSColor.white.withAlphaComponent(0.45)

        let node = SCNNode()
        node.light = light
        return node
    }

    private static func keyLightNode() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.color = NSColor.white
        light.intensity = 700

        let node = SCNNode()
        node.light = light
        node.eulerAngles = SCNVector3(-0.85, 0.35, 0)
        return node
    }

    private static func gridNode() -> SCNNode {
        var points: [SCNVector3] = []
        let extent: Float = 1.82
        let step: Float = 0.45
        var value = -extent

        while value <= extent + 0.001 {
            points.append(SCNVector3(-extent, 0.002, value))
            points.append(SCNVector3(extent, 0.002, value))
            points.append(SCNVector3(value, 0.002, -extent))
            points.append(SCNVector3(value, 0.002, extent))
            value += step
        }

        return lineNode(points: points, color: NSColor.separatorColor.withAlphaComponent(0.28))
    }

    private static func horizonNode() -> SCNNode {
        let segments = 96
        let radius: Float = 1.72
        let points = (0...segments).map { index in
            let angle = Float(index) / Float(segments) * 2 * .pi
            return SCNVector3(cos(angle) * radius, 0.01, sin(angle) * radius)
        }

        return connectedLineNode(points: points, color: NSColor.secondaryLabelColor.withAlphaComponent(0.42))
    }

    private static func pathNode(samples: [SunPathSample3D]) -> SCNNode {
        let points = samples.map(scenePoint)
        return connectedLineNode(points: points, color: NSColor.systemYellow.withAlphaComponent(0.9))
    }

    private static func pathMarkersNode(samples: [SunPathSample3D]) -> SCNNode {
        let parent = SCNNode()
        let sphere = SCNSphere(radius: 0.024)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemYellow.withAlphaComponent(0.95)
        material.emission.contents = NSColor.systemYellow.withAlphaComponent(0.25)
        sphere.materials = [material]

        for sample in samples {
            let node = SCNNode(geometry: sphere.copy() as? SCNGeometry)
            node.position = scenePoint(for: sample)
            parent.addChildNode(node)
        }

        return parent
    }

    private static func currentSunNode(sample: SunPathSample3D) -> SCNNode {
        let sphere = SCNSphere(radius: 0.095)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemYellow
        material.emission.contents = NSColor.systemOrange.withAlphaComponent(0.45)
        sphere.materials = [material]

        let node = SCNNode(geometry: sphere)
        node.position = scenePoint(for: sample)
        return node
    }

    private static func currentVectorNode(sample: SunPathSample3D) -> SCNNode {
        connectedLineNode(
            points: [SCNVector3(0, 0.04, 0), scenePoint(for: sample)],
            color: NSColor.systemOrange.withAlphaComponent(0.85)
        )
    }

    private static func shadowNode(sample: SunPathSample3D) -> SCNNode {
        guard let shadowDirection = sample.shadowDirection else {
            return SCNNode()
        }

        let elevationFactor = max(0, min(sample.elevationDegrees / 80, 1))
        let length = Float(0.85 + ((1 - elevationFactor) * 1.25))
        let end = SCNVector3(
            Float(shadowDirection.x) * length,
            0.018,
            -Float(shadowDirection.z) * length
        )

        return connectedLineNode(
            points: [SCNVector3(0, 0.018, 0), end],
            color: NSColor.systemBlue.withAlphaComponent(0.84)
        )
    }

    private static func referencePostNode() -> SCNNode {
        let cylinder = SCNCylinder(radius: 0.035, height: 0.42)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.labelColor.withAlphaComponent(0.72)
        cylinder.materials = [material]

        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3(0, 0.21, 0)
        return node
    }

    private static func scenePoint(for sample: SunPathSample3D) -> SCNVector3 {
        let direction = sample.direction
        let radius = 1.42
        let height = max(direction.y * 1.18, 0.025)

        return SCNVector3(
            Float(direction.x * radius),
            Float(height),
            Float(-direction.z * radius)
        )
    }

    private static func lineNode(points: [SCNVector3], color: NSColor) -> SCNNode {
        guard points.count >= 2 else {
            return SCNNode()
        }

        let source = SCNGeometrySource(vertices: points)
        let indices = Array(UInt32(0)..<UInt32(points.count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [lineMaterial(color: color)]
        return SCNNode(geometry: geometry)
    }

    private static func connectedLineNode(points: [SCNVector3], color: NSColor) -> SCNNode {
        guard points.count >= 2 else {
            return SCNNode()
        }

        var segmentPoints: [SCNVector3] = []
        for (start, end) in zip(points, points.dropFirst()) {
            segmentPoints.append(start)
            segmentPoints.append(end)
        }

        return lineNode(points: segmentPoints, color: color)
    }

    private static func lineMaterial(color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.32)
        material.lightingModel = .constant
        return material
    }
}
