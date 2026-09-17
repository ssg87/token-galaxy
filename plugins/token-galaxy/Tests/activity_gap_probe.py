"""A reply stays active between real JSONL writes, then settles on completion."""
from pathlib import Path
import datetime,json,os,sqlite3,subprocess,tempfile,time
root=Path(__file__).resolve().parents[1]
app=root/'Outputs/Token Galaxy.app/Contents/MacOS/TokenGalaxy'
with tempfile.TemporaryDirectory(prefix='galaxy-activity-gap-') as td:
 home=Path(td);out=home/'probe';out.mkdir();log=home/'fixture.jsonl';log.write_text('')
 db=sqlite3.connect(home/'state_5.sqlite');db.execute('CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,tokens_used INTEGER,rollout_path TEXT,source TEXT,updated_at INTEGER)');db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?)',('fixture','Synthetic reply',td,100,str(log),'{}',int(time.time())));db.commit();db.close()
 def append(kind,payload):
  with log.open('a') as f:f.write(json.dumps({'timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat(),'type':kind,'payload':payload})+'\n')
 p=subprocess.Popen([str(app)],env=dict(os.environ,CODEX_HOME=td,TOKEN_GALAXY_CLAUDE_HOME=td+'/claude',TOKEN_GALAXY_PROBE_DIR=str(out)),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 def status():return json.loads((out/'status.json').read_text())
 def wait(pred):
  end=time.monotonic()+15
  while time.monotonic()<end:
   assert p.poll() is None
   try:
    x=status()
    if pred(x):return x
   except (OSError,json.JSONDecodeError):pass
   time.sleep(.1)
  raise AssertionError('Activity transition timed out')
 try:
  wait(lambda x:x['scene']['records']==1)
  append('event_msg',{'type':'task_started'})
  append('response_item',{'type':'message','role':'assistant','content':[{'type':'output_text','text':'fixture'}]})
  wait(lambda x:'生成回复' in x['scene']['eventPhases'])
  time.sleep(5)
  rates=[]
  for _ in range(10):
   x=status();rates.append(x['scene']['leadRotationRate']);assert x['observedTokens']==0;time.sleep(.5)
  assert min(rates)>.239,rates
  append('event_msg',{'type':'task_complete'})
  final=wait(lambda x:abs(x['scene']['leadRotationRate']-.01125)<.0001)
  assert final['observedTokens']==0
  print(json.dumps({'pass':True,'minimumReplyRotation':min(rates),'completedRotation':final['scene']['leadRotationRate'],'inventedTokens':0}))
 finally:p.terminate();p.wait(timeout=5)
