#if os(iOS)
import MarketplaceDesignSystem
import SwiftUI
import UIKit

/// Small, once-baked reference-derived textures; no downloads or AI generation.
@MainActor
enum DastakGrocerySceneTextures {
    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
                blue: CGFloat(hex & 255)/255, alpha: 1)
    }
    private static func image(_ width: Int, _ height: Int, paint: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image {
            paint($0.cgContext)
        }
    }
    private static func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat,
                             size: CGFloat, ink: UIColor, bold: Bool = false) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (value as NSString).draw(in: CGRect(x:x,y:y,width:width,height:size*1.5), withAttributes: [
            .font: UIFont.systemFont(ofSize:size,weight:bold ? .bold : .regular),
            .foregroundColor: ink, .paragraphStyle: style
        ])
    }
    static func package(_ family: Int) -> UIImage {
        image(128,256) { ctx in
            let i = family % 12
            color(DastakGrocerySceneReference.packageColors[i]).setFill(); ctx.fill(CGRect(x:0,y:0,width:128,height:256))
            let ink = i % 4 == 1 ? color(0x23362c) : color(0xfff6e4)
            color(i % 2 == 0 ? 0x182e27 : 0xffffee).setFill(); ctx.fill(CGRect(x:0,y:0,width:128,height:26))
            text("DASTAK PANTRY",x:0,y:7,width:128,size:10,ink:i % 2 == 0 ? .white : color(0x243629),bold:true)
            text(DastakGrocerySceneReference.packageNames[i],x:3,y:43,width:122,size:i == 9 ? 19 : 23,ink:ink,bold:true)
            text(i % 2 == 0 ? "SELECT COLLECTION" : "EVERYDAY ESSENTIALS",x:2,y:74,width:124,size:8,ink:ink)
            color(0xf2dfb4).setFill(); ctx.fillEllipse(in:CGRect(x:21,y:115,width:86,height:68))
            for n in 0..<17 {
                let angle = Double(n)*2.4, radius = 6+sqrt(Double(n))*6
                color(n % 3 == 0 ? 0xdbb864 : i % 2 == 0 ? 0x654c2c : 0xa77a39).setFill()
                ctx.saveGState(); ctx.translateBy(x:64+cos(angle)*radius,y:145+sin(angle)*radius*0.6)
                ctx.rotate(by:angle); ctx.fillEllipse(in:CGRect(x:-4,y:-2,width:i % 3 == 0 ? 6 : 12,height:6)); ctx.restoreGState()
            }
            ink.setFill(); ctx.fill(CGRect(x:10,y:205,width:108,height:2))
            text("LOCAL SCENERY",x:0,y:215,width:128,size:9,ink:ink)
            color(0xfffdf5).setFill(); ctx.fill(CGRect(x:88,y:231,width:29,height:18))
            color(0x263027).setFill()
            for n in 0..<11 { ctx.fill(CGRect(x:90+n*2,y:234,width:n % 3 == 0 ? 2 : 1,height:12)) }
        }
    }
    static func ticket() -> UIImage {
        image(256,64) { ctx in
            color(0xf7f4e7).setFill(); ctx.fill(CGRect(x:0,y:0,width:256,height:64))
            color(0xead44c).setFill(); ctx.fill(CGRect(x:0,y:0,width:42,height:64))
            text("PANTRY",x:45,y:8,width:100,size:15,ink:color(0x283530),bold:true)
            color(0x283530).setFill()
            for n in 0..<29 { ctx.fill(CGRect(x:56+n*4,y:35,width:n % 3 == 0 ? 3 : 1,height:17)) }
        }
    }
    static func sign(_ title: String, subtitle: String, background: UInt32 = 0x1d242b) -> UIImage {
        image(1024,256) { ctx in
            color(background).setFill(); ctx.fill(CGRect(x:0,y:0,width:1024,height:256))
            text(title,x:20,y:48,width:984,size:68,ink:.white,bold:true)
            text(subtitle,x:20,y:163,width:984,size:24,ink:color(0xcbd3da))
            color(0xd74345).setFill(); ctx.fill(CGRect(x:0,y:244,width:1024,height:12))
        }
    }
    static func floor() -> UIImage {
        image(512,512) { ctx in
            let colors = [color(0xd2d3cc).cgColor,color(0xdedfd8).cgColor,color(0xd6d7d0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.55,1]) {
                ctx.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:512,y:512),options:[])
            }
            color(0x969b98).setFill(); ctx.fill(CGRect(x:0,y:0,width:2,height:512)); ctx.fill(CGRect(x:0,y:0,width:512,height:2))
            color(0xefefe7).setFill(); ctx.fill(CGRect(x:2,y:2,width:1,height:510)); ctx.fill(CGRect(x:2,y:2,width:510,height:1))
        }
    }
    static func exteriorSign(_ title:String,subtitle:String,emissionMask:Bool=false) -> UIImage {
        if title == "DASTAK" {
            let renderer=ImageRenderer(content:DastakWordmark(size:148)
                .foregroundStyle(Color(red:0.98,green:0.97,blue:0.93)))
            renderer.scale=2
            let wordmark=renderer.uiImage
            // Match the wider physical fascia so lettering is not stretched.
            return image(1744,256) { ctx in
                // Only the lettering emits light; the fascia stays matte at night.
                (emissionMask ? UIColor.black : color(0x202925)).setFill()
                ctx.fill(CGRect(x:0,y:0,width:1744,height:256))
                if let wordmark {
                    let scale=min(1440/wordmark.size.width,224/wordmark.size.height)
                    let size=CGSize(width:wordmark.size.width*scale,height:wordmark.size.height*scale)
                    wordmark.draw(in:CGRect(x:(1744-size.width)/2,y:(256-size.height)/2,width:size.width,height:size.height))
                } else {
                    text("Dastak",x:20,y:20,width:1704,size:148,ink:color(0xfaf2dc))
                }
            }
        }
        return image(1024,256) { ctx in
            color(0x203e34).setFill(); ctx.fill(CGRect(x:0,y:0,width:1024,height:256))
            text(title,x:20,y:43,width:984,size:76,ink:.white,bold:true)
            text(subtitle,x:20,y:163,width:984,size:24,ink:color(0xcbd3da))
            color(0xd74345).setFill(); ctx.fill(CGRect(x:0,y:244,width:1024,height:12))
        }
    }
    static func lighting() -> UIImage {
        image(512,256) { ctx in
            let colors = [color(0x919aa0).cgColor,color(0xd5dcd9).cgColor,color(0x626e68).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.5,1]) {
                ctx.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:0,y:256),options:[])
            }
            UIColor(white:1,alpha:0.75).setFill()
            for x in stride(from:24,through:488,by:96) { ctx.fill(CGRect(x:x,y:34,width:32,height:58)) }
        }
    }
}
#endif
