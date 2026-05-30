enum WorkspaceMode: String, CaseIterable, Identifiable {
    case compress = "压缩"
    case extract = "解压"

    var id: String {
        rawValue
    }
}
