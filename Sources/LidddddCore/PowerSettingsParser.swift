public enum PowerSettingsParser {
  public static func sleepDisabled(in output: String) -> Bool {
    for line in output.split(separator: "\n") {
      let fields = line.split(whereSeparator: { $0.isWhitespace })
      if fields.first?.lowercased() == "sleepdisabled" {
        return fields.last == "1"
      }
    }
    return false
  }
}
