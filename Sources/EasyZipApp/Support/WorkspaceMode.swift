enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case compress = "压缩"
    case extract = "解压"

    var id: String {
        rawValue
    }
}
