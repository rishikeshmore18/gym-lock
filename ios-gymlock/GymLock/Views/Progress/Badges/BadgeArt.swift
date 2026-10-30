//
//  BadgeArt.swift
//  GymLock — Badges
//
//  Loads the baked 3D badge images (<id>.webp, 900x990, in the app bundle) and shows them.
//  Locked = the exact filter used in the approved design: grayscale(1) brightness(0.8) contrast(0.92).
//

import SwiftUI
import UIKit
import CoreText

enum BadgeImages {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// Badge art for an id. Bundle file <id>.webp (preferred) or an asset-catalog image named <id>.
    static func image(for id: String) -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        var img: UIImage?
        if let url = Bundle.main.url(forResource: id, withExtension: "webp") {
            img = UIImage(contentsOfFile: url.path)
        }
        if img == nil { img = UIImage(named: id) }
        if let img { cache.setObject(img, forKey: id as NSString) }
        return img
    }

    /// Decode every badge up front (call once, e.g. when the badges screen appears).
    static func preloadAll() {
        DispatchQueue.global(qos: .userInitiated).async {
            for b in BadgeCatalog.all {
                guard let img = image(for: b.id) else { continue }
                _ = img.preparingForDisplay()
            }
        }
    }
}

/// CSS `grayscale(1) brightness(0.8) contrast(0.92)` as one colour matrix (applied in that order).
enum BadgeLockedFilter {
    static var matrix: ColorMatrix {
        // grayscale (CSS luminance weights) → ×0.8 → contrast 0.92 around 0.5
        let k = 0.8 * 0.92
        let off = Float(0.5 * (1 - 0.92))
        let r = Float(0.2126 * k), g = Float(0.7152 * k), b = Float(0.0722 * k)
        var m = ColorMatrix()
        m.r1 = r; m.r2 = g; m.r3 = b; m.r4 = 0; m.r5 = off
        m.g1 = r; m.g2 = g; m.g3 = b; m.g4 = 0; m.g5 = off
        m.b1 = r; m.b2 = g; m.b3 = b; m.b4 = 0; m.b5 = off
        m.a1 = 0; m.a2 = 0; m.a3 = 0; m.a4 = 1; m.a5 = 0
        return m
    }
}

/// The badge art at a given width (height = width × 1.1).
struct BadgeArtView: View {
    let badge: BadgeDefinition
    var locked: Bool = false
    var width: CGFloat

    var body: some View {
        Canvas { ctx, size in
            guard let ui = BadgeImages.image(for: badge.id) else { return }
            let img = ctx.resolve(Image(uiImage: ui))
            if locked { ctx.addFilter(.colorMatrix(BadgeLockedFilter.matrix)) }
            ctx.draw(img, in: CGRect(origin: .zero, size: size))
        }
        .frame(width: width, height: width * 1.1)
        .accessibilityLabel(Text(badge.name))
    }
}

/// Registers the bundled Oswald fonts once (used by the rank-up titles).
@MainActor
enum GymLockFonts {
    static let semiBold = "Oswald-SemiBold"
    static let bold = "Oswald-Bold"
    private static var done = false

    static func register() {
        guard !done else { return }
        done = true
        for name in [semiBold, bold] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
