"""Real 60-second timer against isolated SQLite/JSONL; no production records."""
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'Outputs/Token Galaxy.app/Contents/MacOS/TokenGalaxy'
OUT = ROOT / 'Outputs/idle-focus-v043'
OUT.mkdir(parents=True, exist_ok=True)

def token(total):
    return json.dumps({'timestamp': dt.datetime.now(dt.timezone.utc).isoformat(), 'type': 'event_msg',
                       'payload': {'type': 'token_count', 'info': {'total_token_usage': {'total_tokens': total}}}})+'\n'

with tempfile.TemporaryDirectory(prefix='galaxy-idle-') as temporary:
    home = Path(temporary)
    db = sqlite3.connect(home/'state_5.sqlite')
    db.execute('CREATE TABLE threads (id TEXT,title TEXT,cwd TEXT,tokens_used INTEGER,rollout_path TEXT,source TEXT,updated_at INTEGER)')
    counts = {'quiet-main': 100_000_000, 'fast-main': 100, 'faster-child': 1_000_000}
    for key, total in counts.items():
        log = home/(key+'.jsonl')
        log.write_text(token(total))
        origin = {'subagent': {'thread_spawn': {'parent_thread_id': 'quiet-main'}}} if key=='faster-child' else {}
        db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?)', (key,key,str(home),total,str(log),json.dumps(origin),int(time.time())+(10 if key=='quiet-main' else 0)))
    db.commit(); db.close()
    transcript = (OUT/'process.log').open('w')
    proc = subprocess.Popen([str(APP)],env=dict(os.environ,CODEX_HOME=str(home),TOKEN_GALAXY_PROBE_DIR=str(OUT)),stdout=transcript,stderr=transcript)
    started = time.monotonic()
    def state():
        try:
            s=json.loads((OUT/'status.json').read_text())
            return s if s['pid']==proc.pid else None
        except (OSError,json.JSONDecodeError):return None
    try:
        deadline=started+18
        while time.monotonic()<deadline:
            s=state()
            if s and s['polls']>=2:break
            assert proc.poll() is None, 'Probe exited'
            time.sleep(.1)
        else:raise AssertionError('No initial sample')
        baseline=s
        last_append=0
        checked_pre_boundary=False
        while time.monotonic()-started<78:
            now=time.monotonic()
            if now-last_append>=1:
                for key, amount in [('fast-main',100),('faster-child',1_000_000)]:
                    counts[key]+=amount
                    with (home/(key+'.jsonl')).open('a') as f:f.write(token(counts[key]));f.flush();os.fsync(f.fileno())
                last_append=now
            s=state()
            assert proc.poll() is None, 'Probe exited'
            if s and s['idleSeconds']<60:
                assert s['selectedTaskID']=='', 'Selected before one full minute'
                if s['idleSeconds']>58:checked_pre_boundary=True
            if s and s['selectedTaskID']:
                assert checked_pre_boundary
                assert s['idleSeconds']>=60
                assert s['selectedTaskID']=='fast-main', 'Auto selected child or quiet high-total parent'
                assert s['scene']['focusID']=='fast-main'
                assert s['selectionMode']=='automatic' and not s['detailsOpen']
                assert s['readOK'] and not s['scene']['rendererError']
                report={'pass':True,'timerSeconds':s['idleSeconds'],'baseline':baseline,'final':s,'scope':'isolated native process; real idle timer; faster child excluded; no physical mouse or Touch Bar capture'}
                (OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
                print(json.dumps({'PASS':'Real 60-second main-only auto focus','seconds':s['idleSeconds'],'selected':s['selectedTaskID'],'report':str(OUT/'report.json')}))
                break
            time.sleep(.1)
        else:raise AssertionError('No automatic selection: '+str(s))
    finally:
        proc.terminate()
        try:proc.wait(timeout=5)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
        transcript.close()
