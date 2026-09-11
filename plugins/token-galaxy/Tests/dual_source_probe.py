from pathlib import Path
import datetime as dt
import json,os,sqlite3,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'Outputs/dual-probe-v060';OUT.mkdir(exist_ok=True)
APP=ROOT/'Outputs/Token Galaxy.app/Contents/MacOS/TokenGalaxy'
def now():return dt.datetime.now(dt.timezone.utc).isoformat()
def cx(n):return json.dumps({'timestamp':now(),'type':'event_msg','payload':{'type':'token_count','info':{'total_token_usage':{'total_tokens':n}}}})+'\n'
def claude(mid,out=40,child=False,block='thinking'):
 return json.dumps({'type':'assistant','sessionId':'session','agentId':'child' if child else None,'isSidechain':child,'timestamp':now(),'uuid':mid+'-'+str(out)+'-'+block,'requestId':'req-'+mid,'message':{'id':mid,'usage':{'input_tokens':10,'cache_creation_input_tokens':20,'cache_read_input_tokens':30,'output_tokens':out},'content':[{'type':block,'name':'Bash'}]}})+'\n'
def append(p,s):
 with p.open('a') as f:f.write(s);f.flush();os.fsync(f.fileno())
with tempfile.TemporaryDirectory(prefix='galaxy-dual-') as tmp:
 home=Path(tmp);cd=home/'claude/projects/test';cd.mkdir(parents=True);cl=cd/'session.jsonl';cl.write_text(claude('a')+claude('a',block='text'));(cd/'session/subagents').mkdir(parents=True);(cd/'session/subagents/child.jsonl').write_text(claude('child',out=10,child=True))
 log=home/'codex.jsonl';log.write_text(cx(1000));db=sqlite3.connect(home/'state_5.sqlite');db.execute('CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,tokens_used INTEGER,rollout_path TEXT,source TEXT,updated_at INTEGER)');db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?)',('c','Codex fixture',str(home),1000,str(log),'{}',int(time.time())));db.commit();db.close()
 trace=(OUT/'process.log').open('w');p=subprocess.Popen([str(APP)],env=dict(os.environ,CODEX_HOME=str(home),TOKEN_GALAXY_CLAUDE_HOME=str(home/'claude'),TOKEN_GALAXY_PROBE_DIR=str(OUT)),stdout=trace,stderr=trace)
 def wait(pred,label,timeout=15):
  end=time.monotonic()+timeout;s=None
  while time.monotonic()<end:
   assert p.poll() is None, 'Probe exited: '+(OUT/'process.log').read_text()
   try:
    s=json.loads((OUT/'status.json').read_text())
    if s['pid']==p.pid and pred(s):return s
   except (OSError,json.JSONDecodeError):pass
   time.sleep(.08)
  raise AssertionError(label+': '+str(s))
 checks=[]
 try:
  base=wait(lambda s:s['polls']>=2 and s['claudeTokens']==170,'baseline')
  assert base['codexTokens']==1000 and base['menuTotalTokens']==1170 and base['observedTokens']==0
  append(cd/'session/subagents/child.jsonl',json.dumps({'type':'user','sessionId':'session','agentId':'child','isSidechain':True,'timestamp':now(),'uuid':'child-only-event','message':{'content':[{'type':'tool_result','tool_use_id':'child-tool'}]}})+'\n')
  child_active=wait(lambda s:s['scene']['claudeWork']>.5 and s['scene']['codexWork']==0,'child-only activity')
  assert child_active['menuTotalTokens']==1170 and child_active['observedTokens']==0
  checks.append('Claude child-only activity drives Claude channel without adding tokens')
  append(log,cx(1100));append(cl,claude('b',out=5,block='tool_use')+claude('b',out=8,block='text'))
  active=wait(lambda s:s['menuTotalTokens']==1338 and s['scene']['codexTokens']>.3 and s['scene']['claudeTokens']>.3,'simultaneous growth')
  assert active['observedTokens']==168 and active['scene']['dualProvider'];checks.append('separate +100 Codex and +68 Claude; both visual drives active')
  append(cl,claude('b',out=8,block='text'));time.sleep(.7)
  duplicate=wait(lambda s:s['polls']>active['polls'],'duplicate sample');assert duplicate['menuTotalTokens']==1338 and duplicate['observedTokens']==168;checks.append('duplicate message did not increase either total')
  split=claude('b',out=18,block='text');append(cl,split[:len(split)//2]);time.sleep(.7)
  partial=wait(lambda s:s['polls']>duplicate['polls'],'partial sample');assert partial['menuTotalTokens']==1338
  append(cl,split[len(split)//2:]);updated=wait(lambda s:s['menuTotalTokens']==1348,'partial completed');assert updated['observedTokens']==178;checks.append('partial JSONL line deferred; output +10 only')
  (home/'state_5.sqlite').rename(home/'state_5.sqlite.offline');append(cl,claude('new',out=20,block='tool_use'))
  failure=wait(lambda s:'codex' in s['sourceErrors'] and s['claudeTokens']==328,'Codex missing, Claude continues')
  assert failure['codexTokens']==1100 and failure['menuTotalTokens']==1428 and failure['scene']['claudeWork']>.2;checks.append('Codex failure retained last total; Claude remained live')
  (home/'state_5.sqlite.offline').rename(home/'state_5.sqlite');final=wait(lambda s:s['readOK'],'recovery')
  (OUT/'report.json').write_text(json.dumps({'PASS':checks,'final':final,'scope':'isolated native process, SQLite and Claude JSONL; no production data writes or hardware capture'},ensure_ascii=False,indent=2));print(json.dumps({'PASS':checks,'report':str(OUT/'report.json')},ensure_ascii=False))
 finally:
  p.terminate();p.wait(timeout=5);trace.close()
