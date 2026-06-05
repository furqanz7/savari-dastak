//
//  SavariButton.swift
//  Savari
//
//  Created by Furqan on 02/11/25.
//


import SwiftUI

extension LinearGradient {
    static let savariDark = LinearGradient(
        colors: [Color.black.opacity(0.96), Color(red: 0.08, green: 0.09, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension Color {
    static let accentBlue = Color(red: 0.3, green: 0.7, blue: 1.0)
    static let accentPurple = Color(red: 0.55, green: 0.3, blue: 1.0)
    static let savariWhite = Color.white.opacity(0.85)
}

struct SavariButton: View {
    let title: String
    var icon: String? = nil
    var gradient: LinearGradient = LinearGradient(
        colors: [.accentBlue, .accentPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                pressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pressed = false }
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon) }
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gradient)
            .cornerRadius(20)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .shadow(color: .white.opacity(0.15), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
    }
}
