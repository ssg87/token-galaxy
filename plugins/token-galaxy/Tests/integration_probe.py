"""Real JSONL append -> reader -> App.apply -> native Metal offscreen frame.
Fixtures and counters live in an isolated temporary CODEX_HOME, never user records.
"""
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time

APP = Path(__file__).resolve().parents[1] / 'Outputs/Token Galaxy.app/Contents/MacOS/TokenGalaxy'
OUT = Path(__file__).resolve().parents[1] / 'Outputs/integration-v4'
OUT.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix='token-galaxy-e2e-') as temporary:
    home = Path(temporary)
    log = home / 'task.jsonl'
    db = sqlite3.connect(home / 'state_5.sqlite')
    db.execute('CREATE TABLE threads (id TEXT, title TEXT, cwd TEXT, tokens_used INTEGER, rollout_path TEXT, source TEXT, updated_at INTEGER)')
    db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?)', ('probe-root', 'Isolated validation', str(home), 1_000_000, str(log), '{}', int(time.time())))
    db.commit()
    def record(kind, payload):
        return (json.dumps({'timestamp': dt.datetime.now(dt.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z'), 'type': kind, 'payload': payload})+'\n').encode()
    def append(bytes_):
        with log.open('ab', buffering=0) as file:
            file.write(bytes_)
            os.fsync(file.fileno())
    def token(total):
        return record('event_msg', {'type':'token_count','info':{'total_token_usage':{'total_tokens':total,'input_tokens':total-100,'cached_input_tokens':800_000,'output_tokens':100},'last_token_usage':{'input_tokens':120_000},'model_context_window':828400}})
    append(token(1_000_000))
    env = dict(os.environ, CODEX_HOME=str(home), TOKEN_GALAXY_PROBE_DIR=str(OUT))
    transcript = (OUT/'process.log').open('w')
    process = subprocess.Popen([str(APP)], env=env, stdout=transcript, stderr=transcript)
    def state():
        try:
            value = json.loads((OUT/'status.json').read_text())
            return value if value['pid']==process.pid else None
        except (OSError, json.JSONDecodeError): return None
    def wait_for(predicate, label, timeout=8):
        end = time.monotonic()+timeout
        while time.monotonic()<end:
            if process.poll() is not None:
                raise AssertionError('Native probe exited: '+(OUT/'process.log').read_text())
            value = state()
            if value and predicate(value): return value
            time.sleep(.05)
        raise AssertionError(label+'; last state='+str(state()))
    checks = []
    try:
        first = wait_for(lambda s:s['polls']>=2 and s['probeFrames']>=2, 'initial baseline', 20)
        assert first['observedTokens']==0
        time.sleep(.6)
        message_at = time.time()
        append(record('response_item', {'type':'message','role':'user','content':[]}) +
               record('response_item', {'type':'function_call_output','call_id':'large-result','output':'x'*420_000}))
        found = wait_for(lambda s:any(e['phase']=='收到消息' for e in s['recentEvents']) and s['scene']['workDrive']>.4, 'message after large append')
        observed = next(e for e in found['recentEvents'] if e['phase']=='收到消息')
        assert found['observedTokens']==0 and found['scene']['tokenDrive']==0
        checks.append({'test':'message followed by 420KB output','latencySeconds':observed['detectedAt']-message_at,'workDrive':found['scene']['workDrive'],'tokens':found['observedTokens'],'frame':found['probeFrames']-1})
        # A message split between writes is not visible until its record terminates.
        split = record('response_item', {'type':'message','role':'user','content':[]})
        halfway = len(split)//2
        append(split[:halfway]); time.sleep(.65)
        before = state(); events_before = before['scene']['receivedEvents']
        append(split[halfway:])
        partial = wait_for(lambda s:s['scene']['receivedEvents']>events_before,'complete split message')
        assert partial['observedTokens']==0
        checks.append({'test':'split JSONL record completed','events':partial['scene']['receivedEvents']})
        for phase in ['function_call','function_call_output']:
            expected = '调用工具' if phase=='function_call' else '工具返回'
            append(record('response_item', {'type':phase,'name':'fixture_tool','call_id':'fixture-call'}))
            value = wait_for(lambda s:s['recentEvents'][-1]['phase']==expected,expected)
            checks.append({'test':expected,'workDrive':value['scene']['workDrive']})
        append(token(1_000_100))
        used = wait_for(lambda s:s['observedTokens']==100 and s['scene']['tokenDrive']>.3, '100 token increment')
        checks.append({'test':'100 token increment','tokenDrive':used['scene']['tokenDrive'],'tokens':used['observedTokens']})
        # The same record data and an unchanged file must not increment again.
        time.sleep(.6)
        assert state()['observedTokens']==100
        append(record('response_item', {'type':'function_call','name':'functions.request_user_input','call_id':'question'}))
        waiting = wait_for(lambda s:s['scene']['spiritMood']==4 and s['recentRecords'][0]['state']=='等待回答', 'explicit question -> waiting pet')
        assert waiting['observedTokens']==100
        append(record('response_item', {'type':'function_call_output','call_id':'question','output':'fixture answer'}))
        answered = wait_for(lambda s:s['recentRecords'][0]['state']!='等待回答' and s['scene']['spiritMood']!=4, 'answer -> leave waiting')
        assert answered['observedTokens']==100
        checks.append({'test':'question and answer -> spirit waiting/resume','tokens':answered['observedTokens']})
        append(record('event_msg', {'type':'task_complete'}))
        done = wait_for(lambda s:s['scene']['eventPhases'][0]=='本轮完成','completion')
        assert done['scene']['rendererError']==''
        report={'checks':checks,'final':done,'scope':'isolated real file -> native app -> Metal offscreen frames; not a physical Touch Bar recording'}
        (OUT/'report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
        print(json.dumps({'PASS':checks,'report':str(OUT/'report.json')},ensure_ascii=False))
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill();process.wait()
        transcript.close()
