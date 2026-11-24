/// What Cadenza Host knows about a macOS permission it can probe but never grant itself.
enum PermissionState: Equatable {
    case notChecked, checking, granted, needed
}
