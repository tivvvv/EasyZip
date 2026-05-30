import Foundation

enum LibArchiveStatus {
    static let ok: Int32 = 0
    static let eof: Int32 = 1
}

enum LibArchiveFileType {
    static let regular: UInt32 = 0o100000
    static let directory: UInt32 = 0o040000
    static let symbolicLink: UInt32 = 0o120000
}

@_silgen_name("archive_error_string")
func archive_error_string(_ archive: OpaquePointer?) -> UnsafePointer<CChar>?

@_silgen_name("archive_read_new")
func archive_read_new() -> OpaquePointer?

@_silgen_name("archive_read_support_filter_all")
func archive_read_support_filter_all(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_support_format_zip")
func archive_read_support_format_zip(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_support_format_7zip")
func archive_read_support_format_7zip(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_support_format_rar")
func archive_read_support_format_rar(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_support_format_rar5")
func archive_read_support_format_rar5(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_support_format_tar")
func archive_read_support_format_tar(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_open_filename")
func archive_read_open_filename(
    _ archive: OpaquePointer?,
    _ filename: UnsafePointer<CChar>?,
    _ blockSize: Int
) -> Int32

@_silgen_name("archive_read_next_header")
func archive_read_next_header(
    _ archive: OpaquePointer?,
    _ entry: UnsafeMutablePointer<OpaquePointer?>
) -> Int32

@_silgen_name("archive_read_data")
func archive_read_data(
    _ archive: OpaquePointer?,
    _ buffer: UnsafeMutableRawPointer?,
    _ length: Int
) -> Int

@_silgen_name("archive_read_data_skip")
func archive_read_data_skip(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_close")
func archive_read_close(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_read_free")
func archive_read_free(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_new")
func archive_write_new() -> OpaquePointer?

@_silgen_name("archive_write_set_format_zip")
func archive_write_set_format_zip(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_set_format_7zip")
func archive_write_set_format_7zip(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_set_format_pax_restricted")
func archive_write_set_format_pax_restricted(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_add_filter_none")
func archive_write_add_filter_none(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_add_filter_gzip")
func archive_write_add_filter_gzip(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_add_filter_bzip2")
func archive_write_add_filter_bzip2(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_add_filter_xz")
func archive_write_add_filter_xz(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_open_filename")
func archive_write_open_filename(
    _ archive: OpaquePointer?,
    _ filename: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("archive_write_header")
func archive_write_header(
    _ archive: OpaquePointer?,
    _ entry: OpaquePointer?
) -> Int32

@_silgen_name("archive_write_data")
func archive_write_data(
    _ archive: OpaquePointer?,
    _ buffer: UnsafeRawPointer?,
    _ length: Int
) -> Int

@_silgen_name("archive_write_finish_entry")
func archive_write_finish_entry(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_close")
func archive_write_close(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_write_free")
func archive_write_free(_ archive: OpaquePointer?) -> Int32

@_silgen_name("archive_entry_new")
func archive_entry_new() -> OpaquePointer?

@_silgen_name("archive_entry_free")
func archive_entry_free(_ entry: OpaquePointer?)

@_silgen_name("archive_entry_pathname_utf8")
func archive_entry_pathname_utf8(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?

@_silgen_name("archive_entry_pathname")
func archive_entry_pathname(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?

@_silgen_name("archive_entry_copy_pathname")
func archive_entry_copy_pathname(
    _ entry: OpaquePointer?,
    _ pathname: UnsafePointer<CChar>?
)

@_silgen_name("archive_entry_symlink_utf8")
func archive_entry_symlink_utf8(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?

@_silgen_name("archive_entry_symlink")
func archive_entry_symlink(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?

@_silgen_name("archive_entry_is_data_encrypted")
func archive_entry_is_data_encrypted(_ entry: OpaquePointer?) -> Int32

@_silgen_name("archive_entry_is_encrypted")
func archive_entry_is_encrypted(_ entry: OpaquePointer?) -> Int32

@_silgen_name("archive_entry_is_metadata_encrypted")
func archive_entry_is_metadata_encrypted(_ entry: OpaquePointer?) -> Int32

@_silgen_name("archive_entry_copy_symlink")
func archive_entry_copy_symlink(
    _ entry: OpaquePointer?,
    _ symlink: UnsafePointer<CChar>?
)

@_silgen_name("archive_entry_filetype")
func archive_entry_filetype(_ entry: OpaquePointer?) -> UInt32

@_silgen_name("archive_entry_set_filetype")
func archive_entry_set_filetype(
    _ entry: OpaquePointer?,
    _ filetype: UInt32
)

@_silgen_name("archive_entry_perm")
func archive_entry_perm(_ entry: OpaquePointer?) -> UInt32

@_silgen_name("archive_entry_set_perm")
func archive_entry_set_perm(
    _ entry: OpaquePointer?,
    _ permissions: UInt32
)

@_silgen_name("archive_entry_size")
func archive_entry_size(_ entry: OpaquePointer?) -> Int64

@_silgen_name("archive_entry_size_is_set")
func archive_entry_size_is_set(_ entry: OpaquePointer?) -> Int32

@_silgen_name("archive_entry_set_size")
func archive_entry_set_size(
    _ entry: OpaquePointer?,
    _ size: Int64
)

@_silgen_name("archive_entry_mtime")
func archive_entry_mtime(_ entry: OpaquePointer?) -> Int64

@_silgen_name("archive_entry_mtime_is_set")
func archive_entry_mtime_is_set(_ entry: OpaquePointer?) -> Int32

@_silgen_name("archive_entry_set_mtime")
func archive_entry_set_mtime(
    _ entry: OpaquePointer?,
    _ seconds: Int64,
    _ nanoseconds: Int64
)
