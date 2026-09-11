"""Verify global menu sum includes records outside the 80-node view."""
from pathlib import Path
import datetime as dt
import json, os, sqlite3, subprocess, tempfile, time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Outputs/menu-total-v051';OUT.mkdir(exist_ok=True)
APP=ROOT/'Outputs/Token Galaxy.app/Contents/MacOS/TokenGalaxy'
def token(n):return json.dumps({'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),'type':'event_msg','payload':{'type':'token_count','info':{'total_token_usage':{'total_tokens':n}}}})+'\n'
with tempfile.TemporaryDirectory(prefix='galaxy-total-') as temporary:
 home=Path(temporary);db=sqlite3.connect(home/'state_5.sqlite');db.execute('CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,tokens_used INTEGER,rollout_path TEXT,source TEXT,updated_at INTEGER,archived INTEGER)')
 for i in range(82):
  log=home/f'{i}.jsonl';log.write_text(token(1000+i+(500 if i==81 else 0)))
  source=json.dumps({'subagent':{'thread_spawn':{'parent_thread_id':'81'}}}) if i==80 else '{}'
  db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?)',(str(i),str(i),str(home),1000+i,str(log),source,i,int(i==0)))
 db.commit();expected=sum(1000+i for i in range(82))+500
 log=(OUT/'process.log').open('w');p=subprocess.Popen([str(APP)],env=dict(os.environ,CODEX_HOME=str(home),TOKEN_GALAXY_PROBE_DIR=str(OUT)),stdout=log,stderr=log)
 def wait(total):
  end=time.monotonic()+18
  while time.monotonic()<end:
   try:
    s=json.loads((OUT/'status.json').read_text())
    if s['pid']==p.pid and s.get('menuTotalTokens')==total:return s
   except (OSError,json.JSONDecodeError):pass
   assert p.poll() is None, 'Probe exited'
   time.sleep(.1)
  raise AssertionError('Wrong aggregate: '+str(s))
 try:
  s=wait(expected);assert s['menuRecordCount']==82 and s['scene']['records']==80 and s['menuLogOverrides']==80
  db.execute('UPDATE threads SET tokens_used=tokens_used+700 WHERE id=?',('0',));db.commit()
  with (home/'81.jsonl').open('a') as f:f.write(token(1681));f.flush();os.fsync(f.fileno())
  s=wait(expected+800);assert s['readOK'] and s['observedTokens']==100
  report={'pass':True,'initialExpected':expected,'updatedExpected':expected+800,'scope':'82 local rows including archived and subagent; 80 recent log overrides; older index updates; 100 actual new tokens','final':s}
  (OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({k:report[k] for k in ['pass','initialExpected','updatedExpected','scope']},ensure_ascii=False))
 finally:
  p.terminate();p.wait(timeout=5);log.close();db.close()
