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
    static func package(_ family: Int, variant: Int = 0) -> UIImage {
        image(128,256) { ctx in
            let i = family % DastakGrocerySceneReference.packageNames.count
            let base = color(DastakGrocerySceneReference.packageColors[i])
            let cream = color(0xf6edda), dark = color(0x23382f)
            let lightPack = [1,4,5,12,13,14,15,17].contains(i)
            let ink = lightPack ? dark : cream
            base.setFill(); ctx.fill(CGRect(x:0,y:0,width:128,height:256))
            // Three distinct label compositions, with a second restrained colourway.
            // Textures are baked once and shared by all facings of that pack.
            if variant == 1 {
                cream.withAlphaComponent(0.3).setFill()
                ctx.fill(CGRect(x:0,y:0,width:128,height:256))
            }
            if i % 3 == 0 {
                cream.setFill(); ctx.fill(CGRect(x:8,y:33,width:112,height:65))
            } else if i % 3 == 1 {
                ink.withAlphaComponent(0.13).setFill()
                for x in stride(from:0,to:128,by:16) { ctx.fill(CGRect(x:x,y:0,width:5,height:256)) }
            } else {
                cream.withAlphaComponent(0.8).setFill()
                ctx.move(to:CGPoint(x:0,y:180)); ctx.addLine(to:CGPoint(x:128,y:148)); ctx.addLine(to:CGPoint(x:128,y:256))
                ctx.addLine(to:CGPoint(x:0,y:256)); ctx.closePath(); ctx.fillPath()
            }
            text(i >= 12 ? "DASTAK / CHILLED" : "DASTAK / PANTRY",x:0,y:12,width:128,size:9,ink:ink,bold:true)
            text(DastakGrocerySceneReference.packageNames[i],x:3,y:45,width:122,size:i == 9 ? 19 : 22,
                 ink:i % 3 == 0 ? dark : ink,bold:true)
            let subtitles = ["WHOLE GRAINS","ROLLED OATS","GROUND SPICES","LEAF TEA","GOLDEN BITES","DURUM WHEAT",
                             "DARK COCOA","FRUIT BLEND","ROASTED BEANS","BAKED CRACKERS","MIXED NUTS","STILL WATER",
                             "FRESH MILK","CULTURED DAIRY","BERRY YOGHURT","CITRUS JUICE","APPLE JUICE","CULTURED MILK"]
            text(subtitles[i],x:2,y:77,width:124,size:8,ink:i % 3 == 0 ? dark : ink)
            motif(i,context:ctx)
            dark.withAlphaComponent(0.8).setFill(); ctx.fill(CGRect(x:10,y:205,width:108,height:1))
            text(i >= 12 ? "KEEP CHILLED" : "PANTRY COLLECTION",x:0,y:216,width:128,size:8,ink:i % 3 == 2 ? dark : ink)
            color(0xfffdf5).setFill(); ctx.fill(CGRect(x:88,y:231,width:29,height:18))
            color(0x263027).setFill()
            for n in 0..<11 { ctx.fill(CGRect(x:90+n*2,y:234,width:n % 3 == 0 ? 2 : 1,height:12)) }
        }
    }

    private static func motif(_ family: Int, context ctx: CGContext) {
        if [7,14,15,16].contains(family) {
            // Citrus wedges, berries and apples have their own silhouettes.
            let fruit = family == 15 ? color(0xf5b448) : family == 16 ? color(0x93b767) : color(0xa74756)
            color(0xfaf1d7).setFill(); ctx.fillEllipse(in:CGRect(x:25,y:112,width:78,height:78))
            fruit.setFill(); ctx.fillEllipse(in:CGRect(x:31,y:118,width:66,height:66))
            if family == 15 {
                ctx.setStrokeColor(color(0xffefc0).cgColor); ctx.setLineWidth(2)
                for n in 0..<8 {
                    let a=Double(n)*Double.pi/4
                    ctx.move(to:CGPoint(x:64,y:151)); ctx.addLine(to:CGPoint(x:64+cos(a)*30,y:151+sin(a)*30)); ctx.strokePath()
                }
            } else {
                color(0x436b43).setFill(); ctx.fillEllipse(in:CGRect(x:60,y:106,width:23,height:10))
                color(0xffefd5).withAlphaComponent(0.5).setFill(); ctx.fillEllipse(in:CGRect(x:43,y:130,width:9,height:18))
            }
        } else if [11,12,13,17].contains(family) {
            color(0xffffff).setFill()
            let drop=UIBezierPath(); drop.move(to:CGPoint(x:64,y:108))
            drop.addCurve(to:CGPoint(x:64,y:185),controlPoint1:CGPoint(x:5,y:167),controlPoint2:CGPoint(x:42,y:185))
            drop.addCurve(to:CGPoint(x:64,y:108),controlPoint1:CGPoint(x:104,y:185),controlPoint2:CGPoint(x:110,y:164))
            drop.fill()
            color(0x78aab7).setStroke(); ctx.setLineWidth(3)
            ctx.move(to:CGPoint(x:20,y:194)); ctx.addQuadCurve(to:CGPoint(x:108,y:194),control:CGPoint(x:64,y:178)); ctx.strokePath()
        } else if family == 3 {
            ctx.setStrokeColor(color(0xd5dbaa).cgColor); ctx.setLineWidth(3)
            ctx.move(to:CGPoint(x:45,y:187)); ctx.addLine(to:CGPoint(x:80,y:112)); ctx.strokePath()
            for n in 0..<5 {
                color(n%2 == 0 ? 0x9ba56b : 0xd0d8a2).setFill()
                ctx.saveGState(); ctx.translateBy(x:51+Double(n)*6,y:174-Double(n)*13); ctx.rotate(by:n%2 == 0 ? -0.6 : 0.6)
                ctx.fillEllipse(in:CGRect(x:-17,y:-8,width:34,height:14)); ctx.restoreGState()
            }
        } else {
            for n in 0..<13 {
                let a=Double(n)*2.4, r=7+sqrt(Double(n))*7
                let cocoa = family == 6 || family == 8
                color(cocoa ? (n%2 == 0 ? 0x573a2b : 0x8c6145) : (n%2 == 0 ? 0xdab46f : 0xf0d696)).setFill()
                ctx.saveGState(); ctx.translateBy(x:64+cos(a)*r,y:151+sin(a)*r*0.85); ctx.rotate(by:a)
                if family == 9 || family == 4 {
                    ctx.fill(CGRect(x:-9,y:-7,width:18,height:14))
                } else {
                    ctx.fillEllipse(in:CGRect(x:-9,y:-4,width:18,height:family == 5 ? 5 : 8))
                }
                ctx.restoreGState()
            }
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
