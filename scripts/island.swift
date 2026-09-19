// Sends a command to a Pulse launched with PULSE_DEV_HOOKS=1: switcher | clipboard | dismiss | up | down | pin | delete | clear | lock | lockfail | unlock
import Foundation
let command = CommandLine.arguments.dropFirst().first ?? "switcher"
DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("dev.pulse.Pulse.command"), object: command, userInfo: nil, deliverImmediately: true)
