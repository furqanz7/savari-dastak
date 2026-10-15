#if os(iOS)
import SwiftUI
import UIKit

/// Decorative sky, not an astronomical forecast. Noise is baked once, drift is paused off-screen.
struct DastakNativeSky: View {
    let weather:DastakEnvironmentWeather
    let reducedMotion:Bool
    let active:Bool
    private static let clouds:UIImage = {
        let width=512,height=128
        var pixels=Array(repeating:UInt8(0),count:width*height*4)
        func hash(_ x:Int,_ y:Int,_ period:Int)->Double {
            let wrapped=(x%period+period)%period
            var random=DastakNativeSceneGeometry.Random(seed:UInt32(truncatingIfNeeded:wrapped &* 374761393) &+ UInt32(truncatingIfNeeded:y &* 668265263) &+ 674)
            _=random.next(); return random.next()
        }
        func noise(_ x:Double,_ y:Double,_ period:Int)->Double {
            let i=Int(floor(x)),j=Int(floor(y)),u=x-floor(x),v=y-floor(y)
            let a=u*u*(3-2*u),b=v*v*(3-2*v)
            let top=hash(i,j,period)*(1-a)+hash(i+1,j,period)*a
            let bottom=hash(i,j+1,period)*(1-a)+hash(i+1,j+1,period)*a
            return top*(1-b)+bottom*b
        }
        for y in 0..<height { for x in 0..<width {
            var value=0.0
            for (frequency,weight) in [(4,0.55),(8,0.25),(16,0.13),(32,0.07)] {
                value += noise(Double(x)/Double(width)*Double(frequency),Double(y)/Double(height)*Double(frequency)*0.6,frequency)*weight
            }
            let t=min(1,max(0,(value-0.40)/0.28))
            let edge=pow(sin(Double(y)/Double(height-1)*Double.pi),0.8)
            let alpha=UInt8(min(255,max(0,t*t*(3-2*t)*edge*255)))
            let offset=(y*width+x)*4
            pixels[offset]=alpha; pixels[offset+1]=alpha; pixels[offset+2]=alpha; pixels[offset+3]=alpha
        } }
        let data=Data(pixels) as CFData
        guard let provider=CGDataProvider(data:data),let image=CGImage(width:width,height:height,bitsPerComponent:8,
            bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,
            decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { return UIImage() }
        return UIImage(cgImage:image)
    }()
    var body:some View {
        let day=min(1,max(0,weather.daylight)),cover=min(1,max(0,weather.cloud))
        ZStack {
            LinearGradient(colors:[color(day,top:true),color(day,top:false)],startPoint:.top,endPoint:.bottom)
            TimelineView(.animation(minimumInterval:1/15,paused:reducedMotion || !active)) { timeline in
                Canvas { context,size in
                    if day<0.4 {
                        var random=DastakNativeSceneGeometry.Random(seed:421)
                        for _ in 0..<70 {
                            let x=random.next()*size.width,y=random.next()*size.height*0.35,r=0.45+random.next()*0.5
                            context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:r*2,height:r*2)),with:.color(.white.opacity((1-day)*(1-cover)*0.45)))
                        }
                        // Decorative moon placement; no claim about the user's actual moon phase.
                        context.fill(Path(ellipseIn:CGRect(x:size.width*0.75,y:size.height*0.09,width:12,height:12)),
                            with:.color(Color(red:0.75,green:0.81,blue:0.88).opacity((1-day)*(1-cover))))
                    }
                    let speed=0.002+min(60,max(0,weather.wind))*0.0001
                    let seconds=reducedMotion || !active ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:100_000)
                    let span=size.width*1.8,drift=(seconds*speed).truncatingRemainder(dividingBy:1)*span
                    var cloud=context.resolve(Image(uiImage:Self.clouds).renderingMode(.template))
                    cloud.shading = .color(Color(white:0.16+day*0.76))
                    context.opacity=0.12+cover*0.86
                    for i in -1...1 {
                        context.draw(cloud,in:CGRect(x:Double(i)*span-drift,y:-size.height*0.03,width:span,height:size.height*0.40))
                    }
                }
            }
        }
    }
    private func color(_ day:Double,top:Bool)->Color {
        let cover=min(1,max(0,weather.cloud))*0.85
        // Overcast skies desaturate toward cool grey; adding red while removing
        // green made the half-daylight rain preset visibly purple.
        let grey=top ? 0.39 : 0.66
        let red=(top ? 0.22 : 0.65)*(1-cover)+grey*cover
        let green=(top ? 0.45 : 0.76)*(1-cover)+(grey+0.015)*cover
        let blue=(top ? 0.68 : 0.81)*(1-cover)+(grey+0.035)*cover
        return Color(red:0.025+red*day,green:0.045+green*day,blue:0.095+blue*day)
    }
}
#endif
