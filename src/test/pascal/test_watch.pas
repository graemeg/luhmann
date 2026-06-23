program watch_test;
uses Luhmann.Ports, Luhmann.Adapters, Luhmann.Watch;
var Pass, Fail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
var
  Ports: TPorts;
  W: TPollingWatcher;
  cs: TChangeSet;
begin
  Pass:=0; Fail:=0;
  { Self-contained fixture: create a fresh notes dir for this run. }
  ForceDirectories('/tmp/luh-watch');
  WriteFile('/tmp/luh-watch/a.adoc', '= A');
  WriteFile('/tmp/luh-watch/b.adoc', '= B');
  Ports := TPorts.Create();
  Ports.Repo := TFilesystemNoteRepository.Create('/tmp/luh-watch');
  W := TPollingWatcher.Create(Ports);
  W.Prime();

  cs := W.Poll();
  Check('no changes after prime', cs.IsEmpty());

  WriteFile('/tmp/luh-watch/c.adoc', '= C');
  cs := W.Poll();
  Check('1 created', cs.Created.Count = 1);
  Check('created is c', (cs.Created.Count=1) and (cs.Created.Get(0) = 'c.adoc'));

  DeleteFile('/tmp/luh-watch/a.adoc');
  cs := W.Poll();
  Check('1 deleted', cs.Deleted.Count = 1);
  Check('deleted is a', (cs.Deleted.Count=1) and (cs.Deleted.Get(0) = 'a.adoc'));

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
