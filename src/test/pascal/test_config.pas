program config_test;
uses Luhmann.Config;
var Pass, Fail: Integer; c: TConfig;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
begin
  Pass:=0; Fail:=0;
  { Self-contained fixture. }
  ForceDirectories('/tmp/luh-watch');
  WriteFile('/tmp/luh-watch/.luhmann.ini',
    'port = 8080'#10'editor = nvim-qt'#10'catch-all-label = inbox'#10'# a comment'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  Check('default port', c.Port = 2022);
  Check('trailing slash stripped', c.RootDir = '/tmp/luh-watch');
  Check('default catchall', c.CatchAll = 'unfiled');
  Check('luhmann dir', c.LuhmannDir = '/tmp/luh-watch/.luhmann');
  Check('site dir', c.SiteDir() = '/tmp/luh-watch/.luhmann/site');
  c.LoadOverrides();
  Check('port override', c.Port = 8080);
  Check('editor override', c.Editor = 'nvim-qt');
  Check('catchall override', c.CatchAll = 'inbox');
  c.Free();
  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
