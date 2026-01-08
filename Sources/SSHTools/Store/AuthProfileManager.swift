import Foundation
import SwiftUI

class AuthProfileManager: ObservableObject {
    static let shared = AuthProfileManager()
    
    @Published var profiles: [SSHAuthProfile] = [] {
        didSet {
            save()
        }
    }
    
    private let key = "ssh_auth_profiles"
    
    init() {
        load()
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SSHAuthProfile].self, from: data) {
            profiles = decoded
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    func addProfile(_ profile: SSHAuthProfile) {
        profiles.append(profile)
    }
    
    func updateProfile(_ profile: SSHAuthProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        }
    }
    
    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
    }
}
