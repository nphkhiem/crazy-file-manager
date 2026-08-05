import Darwin

enum ProcessMemoryProbe {
  static func currentResidentBytes() -> Int64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { infoPointer -> kern_return_t in
      infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), integerPointer, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      return 0
    }
    return Int64(info.resident_size)
  }
}
