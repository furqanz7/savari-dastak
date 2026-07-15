import SwiftUI
import UIKit

#if targetEnvironment(simulator)
func simulatorCaptureImage(title: String) -> UIImage {
    let size = CGSize(width: 800, height: 600)
    return UIGraphicsImageRenderer(size: size).image { context in
        UIColor.systemGray6.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 52, weight: .semibold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
        let text = "\(title) capture\nSimulator smoke test"
        let rect = CGRect(x: 40, y: 235, width: size.width - 80, height: 140)
        text.draw(in: rect, withAttributes: attributes)
    }
}
#endif

struct UploadCard: View {
    let title: String
    let subtitle: String
    let systemIcon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accent.opacity(0.25), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
    }
}
