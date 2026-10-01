// Read-only network probe using Sparkle's real signed-feed parser.
// Only accepts an isolated bundle ending in .update-test, never the installed app.
import AppKit
import Sparkle
final class Probe:NSObject,SPUUpdaterDelegate {
    var finished=false,result="",failure:Error?
    func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem){result="available:"+item.versionString;finished=true}
    func updaterDidNotFindUpdate(_ updater:SPUUpdater){result="up-to-date";finished=true}
    func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?){if !finished{failure=error;finished=true}}
}
let configurationOnly=CommandLine.arguments.contains("--configuration-only")
guard [2,3].contains(CommandLine.arguments.count),let bundle=Bundle(path:CommandLine.arguments[1]),let id=bundle.bundleIdentifier,id.hasSuffix(".update-test") else{fatalError("Use an isolated .update-test bundle")}
let defaults=UserDefaults(suiteName:id)!
defaults.set(false,forKey:"SUEnableAutomaticChecks");defaults.set(false,forKey:"SUAutomaticallyUpdate")
defer{defaults.removePersistentDomain(forName:id)}
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
let probe=Probe(),driver=SPUStandardUserDriver(hostBundle:bundle,delegate:nil)
let updater=SPUUpdater(hostBundle:bundle,applicationBundle:bundle,userDriver:driver,delegate:probe)
do {
    try updater.start()
    if configurationOnly {print("PASS: Sparkle startup configuration accepted without network check")} else {
    updater.checkForUpdateInformation()
    let deadline=Date(timeIntervalSinceNow:45)
    while !probe.finished && Date()<deadline{RunLoop.current.run(until:Date(timeIntervalSinceNow:0.05))}
    if let error=probe.failure{throw error}
    guard probe.finished && !probe.result.isEmpty else{throw NSError(domain:"Probe",code:1,userInfo:[NSLocalizedDescriptionKey:"Feed check timed out or produced no result"])}
    print("PASS: signed feed "+probe.result)
    }
}catch{fputs("Feed probe failed: \(error)\n",stderr);exit(1)}
