"""Verify empty startup and late Claude discovery with no Codex or Touch Bar."""
from pathlib import Path
import datetime,json,os,subprocess,tempfile,time
root=Path(__file__).resolve().parents[1]
app=root/'Outputs/Token Galaxy.app/Contents/MacOS/TokenGalaxy'
with tempfile.TemporaryDirectory(prefix='galaxy-availability-') as tmp:
 home=Path(tmp);out=home/'probe';out.mkdir()
 env=dict(os.environ,CODEX_HOME=str(home),TOKEN_GALAXY_CLAUDE_HOME=str(home/'claude'),TOKEN_GALAXY_PROBE_DIR=str(out),TOKEN_GALAXY_TEST_TOUCH_BAR='0')
 with (out/'process.log').open('w') as log:
  p=subprocess.Popen([str(app)],env=env,stdout=log,stderr=log)
  def wait(pred):
   end=time.monotonic()+15
   while time.monotonic()<end:
    assert p.poll() is None
    try:
     s=json.loads((out/'status.json').read_text())
     if s['pid']==p.pid and pred(s):return s
    except (OSError,json.JSONDecodeError):pass
    time.sleep(.1)
   raise AssertionError('availability transition timed out')
  try:
   s=wait(lambda s:s['capabilities']['providers']==[])
   assert s['readOK'] and not s['capabilities']['touchBar']
   folder=home/'claude/projects/fixture';folder.mkdir(parents=True)
   record={'type':'assistant','sessionId':'fixture','uuid':'fixture-message','requestId':'fixture-request','timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat(),'message':{'id':'fixture-message','usage':{'input_tokens':10,'output_tokens':5},'content':[{'type':'text','text':'fixture'}]}}
   (folder/'fixture.jsonl').write_text(json.dumps(record)+'\n')
   s=wait(lambda s:s['capabilities']['providers']==['claude'])
   assert s['readOK'] and s['claudeTokens']==15 and s['codexRecords']==0
   print('PASS: empty startup; no Touch Bar; late Claude-only discovery without restart')
  finally:p.terminate();p.wait(timeout=5)
