"""Fail publication checks for accidentally tracked local/session artifacts."""
from pathlib import Path
import json,re,subprocess
root=Path(__file__).resolve().parents[1]
files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
assert any(files), 'Run after staging the public files'
bad=[]
for name in filter(None,files):
 p=root/name
 if any(x in p.parts for x in ('Outputs','Backups','__pycache__')) or p.suffix in ('.sqlite','.db','.jsonl'):
  bad.append(name+': private/generated artifact')
 data=p.read_bytes()
 if re.search(rb'/Users/[A-Za-z0-9_.-]+/',data):bad.append(name+': personal absolute path')
 if re.search(rb'(?:sk-[A-Za-z0-9_-]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----)',data):bad.append(name+': credential-like content')
for name in ('.agents/plugins/marketplace.json','plugins/token-galaxy/.codex-plugin/plugin.json'):
 json.loads((root/name).read_text())
assert not bad, '\n'.join(bad)
print('PASS: tracked publication artifacts and manifests')
