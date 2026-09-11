import Foundation
import IOKit

/// Read-only HID metadata detection. No private Touch Bar control API or key-event access.
enum HardwareCapabilities {
    static var touchBarAvailable:Bool {
        if let forced=ProcessInfo.processInfo.environment["TOKEN_GALAXY_TEST_TOUCH_BAR"] {return forced=="1"}
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOHIDDevice"),&iterator)==KERN_SUCCESS else{return false}
        defer{IOObjectRelease(iterator)}
        while true {
            let entry=IOIteratorNext(iterator);if entry==0{break};defer{IOObjectRelease(entry)}
            let product=IORegistryEntryCreateCFProperty(entry,"Product" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? String
            if product=="Touch Bar Display" || product=="TouchBarUserDevice" {return true}
        }
        return false
    }
}
