import Foundation

enum FloatArrayCodec {
    static func encode(_ floats: [Float]) -> Data {
        if floats.isEmpty { return Data() }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data) -> [Float]? {
        if data.isEmpty { return [] }

        if data.count % MemoryLayout<Float>.stride == 0 {
            let floats: [Float]? = data.withUnsafeBytes { rawBuffer in
                let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                guard floatBuffer.count == data.count / MemoryLayout<Float>.stride else { return nil }
                return Array(floatBuffer)
            }
            if let floats { return floats }
        }

        if let legacy = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSNumber.self], from: data) as? [NSNumber] {
            return legacy.map { $0.floatValue }
        }

        return nil
    }
}

