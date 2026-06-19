import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

private let iconShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct IconUniforms {
    uint width;
    uint height;
};

static float clamp01(float value) {
    return clamp(value, 0.0, 1.0);
}

static float smoother(float value) {
    float t = clamp01(value);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static float2 rotate(float2 point, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2((point.x * c) - (point.y * s), (point.x * s) + (point.y * c));
}

static float rounded_rect_alpha(float2 p, float2 center, float2 halfSize, float radius, float feather) {
    float2 q = abs(p - center) - (halfSize - radius);
    float distance = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    return 1.0 - smoother(distance / feather);
}

static float circle_alpha(float2 p, float2 center, float radius, float feather) {
    return 1.0 - smoother((length(p - center) - radius) / feather);
}

static float arc_alpha(float2 p, float2 center, float radius, float lineWidth, float startAngle, float endAngle, float feather) {
    float2 delta = p - center;
    float angle = atan2(delta.y, delta.x);
    if (angle < startAngle) {
        angle += 6.28318530718;
    }
    float normalizedEnd = endAngle;
    if (normalizedEnd < startAngle) {
        normalizedEnd += 6.28318530718;
    }
    float angleMask = step(startAngle, angle) * step(angle, normalizedEnd);
    float radial = abs(length(delta) - radius) - (lineWidth * 0.5);
    return angleMask * (1.0 - smoother(radial / feather));
}

static float4 over(float4 under, float4 overColor) {
    return overColor + under * (1.0 - overColor.a);
}

static float4 premul(float3 color, float alpha) {
    float a = clamp01(alpha);
    return float4(color * a, a);
}

static float3 mix3(float3 a, float3 b, float t) {
    return mix(a, b, clamp01(t));
}

kernel void renderIcon(texture2d<float, access::write> output [[texture(0)]],
                       constant IconUniforms& uniforms [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    float2 size = float2(float(uniforms.width), float(uniforms.height));
    float2 p = (float2(gid) + 0.5) / size;
    float px = 1.0 / min(size.x, size.y);
    float4 color = float4(0.0);

    float body = rounded_rect_alpha(p, float2(0.5, 0.5), float2(0.42, 0.42), 0.12, 2.2 * px);
    float shadow = rounded_rect_alpha(p + float2(-0.015, -0.020), float2(0.5, 0.5), float2(0.42, 0.42), 0.12, 26.0 * px);
    color = over(color, premul(float3(0.02, 0.08, 0.16), 0.20 * shadow * (1.0 - body)));

    float3 skyTop = float3(0.07, 0.56, 0.96);
    float3 skyLeft = float3(0.37, 0.92, 1.00);
    float3 skyLower = float3(0.15, 0.72, 0.90);
    float3 sky = mix3(mix3(skyLeft, skyTop, p.x), skyLower, smoother(p.y));
    sky += float3(0.10, 0.18, 0.20) * circle_alpha(p, float2(0.30, 0.20), 0.34, 0.22);
    sky -= float3(0.00, 0.10, 0.19) * smoother((p.y - 0.62) / 0.28);
    color = over(color, premul(sky, body));

    float topSheen = body * (1.0 - smoother((p.y - 0.19) / 0.20)) * (0.55 + 0.45 * (1.0 - p.x));
    color = over(color, premul(float3(1.0, 1.0, 1.0), 0.16 * topSheen));

    float horizon = 0.675 - 0.075 * pow(abs((p.x - 0.5) / 0.45), 1.75);
    float groundMask = body * smoother((p.y - horizon) / (6.0 * px));
    float3 ground = mix3(float3(0.04, 0.37, 0.66), float3(0.02, 0.20, 0.45), smoother((p.y - 0.66) / 0.28));
    color = over(color, premul(ground, groundMask));
    float horizonLine = body * (1.0 - smoother(abs(p.y - horizon) / (3.2 * px)));
    color = over(color, premul(float3(1.0, 0.98, 0.78), 0.74 * horizonLine));

    float sunShadow = body * circle_alpha(p, float2(0.56, 0.58), 0.16, 0.11) * smoother((p.x + p.y - 0.88) / 0.34);
    color = over(color, premul(float3(0.02, 0.16, 0.25), 0.24 * sunShadow));

    float sunGlow = body * circle_alpha(p, float2(0.50, 0.50), 0.19, 0.14);
    color = over(color, premul(float3(1.0, 0.93, 0.20), 0.30 * sunGlow));
    float sun = circle_alpha(p, float2(0.50, 0.50), 0.132, 3.2 * px);
    float sunLight = circle_alpha(p, float2(0.43, 0.42), 0.16, 0.18);
    float3 sunColor = mix3(float3(1.0, 0.56, 0.02), float3(1.0, 0.95, 0.22), sunLight);
    color = over(color, premul(sunColor, sun));
    float sunRim = circle_alpha(p, float2(0.50, 0.50), 0.136, 1.8 * px) - circle_alpha(p, float2(0.50, 0.50), 0.124, 1.8 * px);
    color = over(color, premul(float3(1.0, 1.0, 0.70), 0.48 * sunRim));

    float arcStart = 3.595378259;
    float arcEnd = 6.108652382;
    float arcBase = arc_alpha(p, float2(0.50, 0.70), 0.355, 0.042, arcStart, arcEnd, 2.2 * px) * body;
    float arcProgress = clamp01((atan2(p.y - 0.70, p.x - 0.50) - arcStart) / (arcEnd - arcStart));
    float3 arcColor = mix3(float3(1.0, 0.96, 0.78), float3(1.0, 0.50, 0.10), smoother(arcProgress));
    color = over(color, premul(arcColor, arcBase));
    float arcHighlight = arc_alpha(p + float2(0.0, 0.010), float2(0.50, 0.70), 0.355, 0.018, arcStart, arcEnd, 2.0 * px) * body;
    color = over(color, premul(float3(1.0, 1.0, 0.93), 0.35 * arcHighlight));

    float2 marker = float2(0.69, 0.34);
    float markerShadow = circle_alpha(p, marker + float2(0.018, 0.020), 0.058, 0.030) * body;
    color = over(color, premul(float3(0.04, 0.12, 0.18), 0.30 * markerShadow));
    float markerOuter = circle_alpha(p, marker, 0.052, 2.2 * px) * body;
    color = over(color, premul(float3(0.98, 0.98, 0.88), markerOuter));
    float markerInner = circle_alpha(p, marker, 0.030, 2.2 * px) * body;
    float markerLift = circle_alpha(p, marker - float2(0.012, 0.014), 0.033, 0.04);
    color = over(color, premul(mix3(float3(1.0, 0.58, 0.03), float3(1.0, 0.92, 0.25), markerLift), markerInner));

    float cloudLeft = circle_alpha(p, float2(0.07, 0.64), 0.055, 2.5 * px)
        + circle_alpha(p, float2(0.12, 0.62), 0.040, 2.5 * px)
        + circle_alpha(p, float2(0.17, 0.65), 0.034, 2.5 * px);
    float cloudRight = circle_alpha(p, float2(0.86, 0.65), 0.050, 2.5 * px)
        + circle_alpha(p, float2(0.92, 0.62), 0.052, 2.5 * px)
        + circle_alpha(p, float2(0.98, 0.66), 0.060, 2.5 * px);
    float cloudMask = body * clamp01(cloudLeft + cloudRight) * (1.0 - groundMask * 0.55);
    color = over(color, premul(float3(1.0, 0.99, 0.88), 0.78 * cloudMask));

    float edge = rounded_rect_alpha(p, float2(0.5, 0.5), float2(0.421, 0.421), 0.12, 2.0 * px)
        - rounded_rect_alpha(p, float2(0.5, 0.5), float2(0.398, 0.398), 0.11, 3.0 * px);
    color = over(color, premul(float3(1.0, 1.0, 1.0), 0.12 * edge));

    output.write(color, gid);
}
"""

@main
struct SunStatusIconRenderer {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let outputURL = root.appendingPathComponent("Assets/AppIconMetal.png")
        let comparisonURL = root.appendingPathComponent("screenshots/pr-evidence/metal-app-icon-comparison.png")

        let image = try MetalIconRenderer(size: 1_024).render()
        try image.writePNG(to: outputURL)
        try ComparisonRenderer.render(
            currentURL: root.appendingPathComponent("Assets/AppIcon.png"),
            metalURL: outputURL,
            outputURL: comparisonURL
        )

        print("Wrote \(outputURL.path)")
        print("Wrote \(comparisonURL.path)")
    }
}

private struct MetalIconRenderer {
    let size: Int

    func render() throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw RenderError.metalUnavailable
        }

        let library = try device.makeLibrary(source: iconShaderSource, options: nil)
        guard let function = library.makeFunction(name: "renderIcon") else {
            throw RenderError.missingFunction
        }

        let pipeline = try device.makeComputePipelineState(function: function)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.commandCreationFailed
        }

        var uniforms = IconUniforms(width: UInt32(size), height: UInt32(size))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<IconUniforms>.stride, index: 0)

        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let threadsPerGroup = MTLSize(width: width, height: height, depth: 1)
        let threads = MTLSize(width: size, height: size, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw error
        }

        return try texture.image()
    }
}

private struct IconUniforms {
    var width: UInt32
    var height: UInt32
}

private enum ComparisonRenderer {
    static func render(currentURL: URL, metalURL: URL, outputURL: URL) throws {
        guard let current = NSImage(contentsOf: currentURL),
              let metal = NSImage(contentsOf: metalURL) else {
            throw RenderError.imageLoadFailed
        }

        let canvasSize = NSSize(width: 1_600, height: 900)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RenderError.imageEncodingFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        drawText("App icon rendering comparison", at: NSPoint(x: 54, y: 810), size: 38, weight: .bold)
        drawCard(image: current, title: "Current PNG source", origin: NSPoint(x: 120, y: 160))
        drawCard(image: metal, title: "Metal-rendered source", origin: NSPoint(x: 860, y: 160))

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.imageEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
    }

    private static func drawCard(image: NSImage, title: String, origin: NSPoint) {
        let card = NSRect(x: origin.x, y: origin.y, width: 620, height: 570)
        NSColor.controlBackgroundColor.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28).fill()

        drawText(title, at: NSPoint(x: origin.x + 34, y: origin.y + 508), size: 24, weight: .bold)
        image.draw(
            in: NSRect(x: origin.x + 110, y: origin.y + 54, width: 400, height: 400),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    private static func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.labelColor
        ]
        text.draw(at: point, withAttributes: attributes)
    }
}

private enum RenderError: Error {
    case metalUnavailable
    case missingFunction
    case commandCreationFailed
    case imageLoadFailed
    case imageEncodingFailed
}

private extension MTLTexture {
    func image() throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw RenderError.imageEncodingFailed
        }

        return cgImage
    }
}

private extension CGImage {
    func writePNG(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RenderError.imageEncodingFailed
        }

        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.imageEncodingFailed
        }
    }
}

private extension NSImage {
    func writePNG(to url: URL) throws {
        var rect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw RenderError.imageEncodingFailed
        }

        try cgImage.writePNG(to: url)
    }
}
