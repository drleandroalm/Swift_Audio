import os

enum Log {
    static let audio  = Logger(subsystem: "com.swift.examples.scribe", category: "AudioPipeline")
    static let speech = Logger(subsystem: "com.swift.examples.scribe", category: "Speech")
    static let state  = Logger(subsystem: "com.swift.examples.scribe", category: "StateMachine")
    static let ui     = Logger(subsystem: "com.swift.examples.scribe", category: "UI")
}

