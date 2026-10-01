import AppKit
import Sparkle

/// The updater only contacts the public release feed; telemetry stays local.
final class AppUpdater:NSObject {
    static let feedURL="https://github.com/ssg87/token-galaxy/releases/latest/download/appcast.xml"
    let controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
    private var started=false
    var enabled:Bool {controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates}
    func start(){guard !started else{return};started=true;controller.startUpdater()}
    func appendMenuItems(to menu:NSMenu){
        menu.addItem(.separator())
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "未知"
        menu.addItem(NSMenuItem(title:"Token 星河 \(version)",action:nil,keyEquivalent:""))
        let check=NSMenuItem(title:"检查更新…",action:#selector(SPUStandardUpdaterController.checkForUpdates(_:)),keyEquivalent:"")
        check.target=controller;menu.addItem(check)
        let automatic=NSMenuItem(title:"自动更新",action:#selector(toggleAutomatic(_:)),keyEquivalent:"")
        automatic.target=self;automatic.state=enabled ? .on:.off
        automatic.toolTip="每天检查新版，自动下载并由系统安排安装；需要确认时会提示。"
        menu.addItem(automatic);menu.addItem(.separator())
    }
    func refreshMenu(_ menu:NSMenu){
        for item in menu.items where item.action == #selector(toggleAutomatic(_:)){item.state=enabled ? .on:.off}
    }
    @objc func toggleAutomatic(_ sender:NSMenuItem){
        let turnOn = !enabled
        // Sparkle only accepts automatic downloads after automatic checks are enabled.
        controller.updater.automaticallyChecksForUpdates=turnOn
        controller.updater.automaticallyDownloadsUpdates=turnOn
        sender.state=turnOn ? .on:.off
    }
}

func runUpdaterConfigurationChecks() throws {
    let info=Bundle.main.infoDictionary ?? [:]
    func require(_ ok:Bool,_ message:String)throws{if !ok{throw NSError(domain:"Updater",code:1,userInfo:[NSLocalizedDescriptionKey:message])}}
    try require(info["SUFeedURL"] as? String==AppUpdater.feedURL,"Unexpected update feed")
    try require(Data(base64Encoded:info["SUPublicEDKey"] as? String ?? "")?.count==32,"Missing update signing key")
    try require(info["SURequireSignedFeed"] as? Bool==true,"Unsigned update feed allowed")
    try require(info["SUVerifyUpdateBeforeExtraction"] as? Bool==true,"Archive verification prerequisite missing")
    try require(info["SUSignedFeedFailureExpirationInterval"] as? Int==0,"Signed feed requirement can expire")
    try require(info["SUEnableSystemProfiling"] as? Bool==false,"System profiling enabled")
    try require(info["SUEnableAutomaticChecks"] as? Bool==true && info["SUAutomaticallyUpdate"] as? Bool==true,"Automatic update defaults missing")
    try require(info["SUSendProfileInfo"] as? Bool==false,"System profile upload enabled")
    try require(Bundle.main.privateFrameworksURL.map{FileManager.default.fileExists(atPath:$0.appendingPathComponent("Sparkle.framework/Sparkle").path)}==true,"Updater framework not bundled")
    print("PASS: signed HTTPS update feed, bundled updater, automatic defaults, no profile upload")
}
