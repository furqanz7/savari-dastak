//
//  SupabaseManager.swift
//  Savari
//

import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    private let supabaseUrl = URL(string: "https://mxpszppootpltifzvjla.supabase.co")!
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im14cHN6cHBvb3RwbHRpZnp2amxhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjAxMjAxNzUsImV4cCI6MjA3NTY5NjE3NX0.ZBN6pr6zP7AkfdWLfmxqjG0QULjmt1djf1bCh2D0l9s"

    lazy var client = SupabaseClient(
        supabaseURL: supabaseUrl,
        supabaseKey: supabaseKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )

    private init() {}
}
