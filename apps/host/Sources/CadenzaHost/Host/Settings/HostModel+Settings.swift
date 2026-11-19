import SwiftUI

extension HostModel {
    /// Binds a setting so each change is saved as soon as it is made, like System Settings.
    /// Settings the running Host reads only at start take effect after `restartToApply()`.
    func committedBinding<Value>(_ keyPath: WritableKeyPath<HostConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { self.configuration[keyPath: keyPath] },
            set: { value in
                self.configuration[keyPath: keyPath] = value
                self.persistConfiguration()
            })
    }

    func persistConfiguration() {
        do {
            try configuration.save()
        } catch {
            showError("Settings could not be saved", error.localizedDescription)
        }
    }

    /// True when a setting in `settings` differs from the configuration the running Host started with.
    func restartPending(_ settings: Set<RestartSetting>) -> Bool {
        guard running, let runningConfiguration = service?.configuration else { return false }
        return configuration.differs(in: settings, from: runningConfiguration)
    }
}
