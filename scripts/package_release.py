#!/usr/bin/env python3
"""Build and sign a universal Sparkle release. Does not push or publish anything."""
from pathlib import Path
import argparse, hashlib, json, os, plistlib, shutil, subprocess, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
PLUGIN=ROOT/'plugins/token-galaxy'
def run(args,**kw):
    return subprocess.run([str(x) for x in args],check=True,**kw)
def info(app):
    return plistlib.loads((app/'Contents/Info.plist').read_bytes())
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--key-file',type=Path,required=True,help='Private Ed25519 signing seed; never put it in the repository')
    parser.add_argument('--reuse-native',action='store_true',help='Reuse the already tested native build; still builds the other architecture')
    parser.add_argument('--notes',type=Path,help='Plain-text release notes')
    args=parser.parse_args()
    key=args.key_file.expanduser().resolve()
    if not key.is_file():raise SystemExit('Signing key file not found')
    if ROOT==key or ROOT in key.parents:raise SystemExit('Signing keys must be outside the repository')
    if key.stat().st_mode & 0o077:raise SystemExit('Signing key must be private: chmod 600 the key file')
    version=json.loads((PLUGIN/'.codex-plugin/plugin.json').read_text())['version']
    output=PLUGIN/'Outputs'/('release-'+version)
    assets=output/'assets';assets.mkdir(parents=True,exist_ok=True)
    if list(assets.iterdir()):raise SystemExit('Release assets already exist; use a new version or move the old assets aside')
    native=os.uname().machine
    builds={}
    for arch in ['x86_64','arm64']:
        if args.reuse_native and arch==native:
            app=PLUGIN/'Outputs/Token Galaxy.app'
        else:
            builddir=output/arch
            env=os.environ.copy();env.update(TOKEN_GALAXY_ARCH=arch,TOKEN_GALAXY_BUILD_DIR=str(builddir))
            run([ROOT/'build.sh'],env=env)
            app=builddir/'Token Galaxy.app'
        meta=info(app)
        if meta['CFBundleShortVersionString']!=version:raise SystemExit('Stale build version')
        run(['lipo',app/'Contents/MacOS/TokenGalaxy','-verify_arch',arch])
        builds[arch]=app
    if info(builds['x86_64'])!=info(builds['arm64']):raise SystemExit('Architecture bundle metadata mismatch')
    app=output/'universal/Token Galaxy.app';app.parent.mkdir(parents=True,exist_ok=True)
    run(['ditto',builds['x86_64'],app])
    run(['lipo','-create',*[builds[a]/'Contents/MacOS/TokenGalaxy' for a in ['x86_64','arm64']],'-output',app/'Contents/MacOS/TokenGalaxy'])
    run(['codesign','--force','--sign','-',app]);run(['codesign','--verify','--deep','--strict',app])
    run([app/'Contents/MacOS/TokenGalaxy','--self-test'])
    archive=assets/('Token-Galaxy-'+version+'-universal.zip')
    run(['ditto','-c','-k','--sequesterRsrc','--keepParent',app,archive])
    notes=args.notes.read_text() if args.notes else 'Token Galaxy '+version+'\nSee the repository changelog for details.'
    archive.with_suffix('.txt').write_text(notes)
    sparkle=Path(subprocess.check_output([str(PLUGIN/'scripts/prepare_sparkle.sh')],text=True).strip())
    run([sparkle/'bin/generate_appcast','--ed-key-file',key,'--download-url-prefix','https://github.com/ssg87/token-galaxy/releases/download/v'+version+'/', '--embed-release-notes','--maximum-deltas','0',assets])
    feed=assets/'appcast.xml'
    run([sparkle/'bin/sign_update','--verify','--ed-key-file',key,feed])
    item=ET.parse(feed).find('./channel/item')
    ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    enclosure=item.find('enclosure');meta=info(app)
    if item.findtext(ns+'version')!=meta['CFBundleVersion']:raise SystemExit('Incorrect feed build version')
    if enclosure.get('length')!=str(archive.stat().st_size):raise SystemExit('Incorrect archive length')
    signature=enclosure.get(ns+'edSignature')
    run([sparkle/'bin/sign_update','--verify','--ed-key-file',key,archive,signature])
    run(['swift',ROOT/'scripts/verify_update_archive.swift',archive,meta['SUPublicEDKey'],signature])
    # Release assets do not need an extra copy of the embedded plain-text notes.
    archive.with_suffix('.txt').unlink()
    hashes=assets/'SHA256SUMS.txt'
    hashes.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in [archive,feed]))
    print('Ready to publish:',assets)
if __name__=='__main__':main()
