// Prints the frame of the given process's main window as an mpv --geometry value ("WxH+X+Y").
// mpv on macOS takes geometry in backing pixels, with Y measured from the top of the visible screen area.
import AppKit

guard CommandLine.arguments.count > 1, let pid = Int(CommandLine.arguments[1]) else { exit(2) }
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
guard let w = mine.first, let b = w[kCGWindowBounds as String] as? [String: CGFloat],
      let screen = NSScreen.screens.first else { exit(1) }
let scale = screen.backingScaleFactor
let topInset = screen.frame.maxY - screen.visibleFrame.maxY
let x = max(0, b["X"]!), y = max(0, b["Y"]! - topInset)
print("\(Int(b["Width"]! * scale))x\(Int(b["Height"]! * scale))+\(Int(x * scale))+\(Int(y * scale))")
