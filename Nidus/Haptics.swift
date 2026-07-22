//
//  Haptics.swift
//  Nidus
//
//  Small cross-platform haptic/feedback tap.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Haptics {
    static func tap() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
