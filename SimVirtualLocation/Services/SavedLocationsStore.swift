import Foundation

final class SavedLocationsStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = AppStorageKey.savedLocations) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [Location] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([Location].self, from: data)) ?? []
    }

    func save(_ locations: [Location]) {
        guard let data = try? JSONEncoder().encode(locations) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
