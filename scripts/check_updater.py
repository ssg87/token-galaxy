#!/usr/bin/env python3
"""Validate Sparkle in an isolated app copy; never start the app or install an update."""
from pathlib import Path
import argparse,plistlib,subprocess,tempfile,uuid
ROOT=Path(__file__).resolve().parents[1]
PLUGIN=ROOT/'plugins/token-galaxy'
def run(args,**kw):return subprocess.run([str(x) for x in args],check=True,**kw)
def main():
    p=argparse.ArgumentParser();p.add_argument('--app',type=Path,required=True);p.add_argument('--online',action='store_true');p.add_argument('--build-offset',type=int,default=0);args=p.parse_args()
    sparkle=Path(subprocess.check_output([str(PLUGIN/'scripts/prepare_sparkle.sh')],text=True).strip())
    with tempfile.TemporaryDirectory(prefix='token-galaxy-updater-') as td:
        root=Path(td);app=root/'Token Galaxy.app';probe=root/'feed-probe'
        run(['ditto',args.app.resolve(),app])
        path=app/'Contents/Info.plist';info=plistlib.loads(path.read_bytes())
        info.update(CFBundleIdentifier='local.token-galaxy.'+uuid.uuid4().hex+'.update-test',CFBundleVersion=str(int(info['CFBundleVersion'])+args.build_offset),SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False)
        path.write_bytes(plistlib.dumps(info));run(['codesign','--force','--sign','-',app])
        run(['xcrun','swiftc','-swift-version','5','-F',sparkle,'-framework','Sparkle','-framework','AppKit','-Xlinker','-rpath','-Xlinker',sparkle,PLUGIN/'Tests/update_feed_probe.swift','-o',probe])
        command=[probe,app]
        if not args.online:command.append('--configuration-only')
        run(command,timeout=55)
if __name__=='__main__':main()
