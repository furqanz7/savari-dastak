import Foundation

enum DastakEnvironmentResources {
    static func url(_ name: String, extension suffix: String? = nil) -> URL? {
        Bundle.module.url(forResource:name,withExtension:suffix)
    }
}
