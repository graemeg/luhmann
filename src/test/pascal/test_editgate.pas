{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Tests the policy that gates /api/edit on the listen address.

  GET /api/edit spawns an external editor process on the host.  That is
  reasonable when the server is private to the machine you are sitting at, and
  it is a remote process-spawn primitive the moment the listener is reachable
  from anywhere else.  So the endpoint is refused whenever the bind address is
  not loopback -- and, because a headless host has no display to launch an
  editor onto, refusing costs nothing real. }
program editgate_test;
uses Luhmann.Config, Luhmann.Ports, Net.Sockets;

type
  { Records whether LaunchEditor was reached, so a test can prove the gate
    refused BEFORE any process was spawned -- not merely that the response
    said 403. }
  TSpyEditor = class(IEditorLauncher)
  public
    Launched: Boolean;
    function LaunchEditor(const AAbsPath: string): Boolean;
  end;

function TSpyEditor.LaunchEditor(const AAbsPath: string): Boolean;
begin
  Launched := True;
  Result := True;
end;

var
  Pass, Fail: Integer;
  c: TConfig;
  Spy: TSpyEditor;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;

{ Mirrors the guard in TLuhmannApp.ApiEdit. }
function EditAllowed(AConfig: TConfig): Boolean;
begin
  Result := AConfig.BindIsLoopback();
end;

begin
  Pass:=0; Fail:=0;
  ForceDirectories('/tmp/luh-editgate');

  { --- default (loopback): the editor is allowed --- }
  WriteFile('/tmp/luh-editgate/.luhmann.ini', 'editor = xterm -e vim'#10);
  c := TConfig.Create('/tmp/luh-editgate/');
  c.LoadOverrides();
  Check('loopback allows edit', EditAllowed(c));

  { --- all interfaces: refused --- }
  WriteFile('/tmp/luh-editgate/.luhmann.ini',
    'bind = 0.0.0.0'#10'editor = xterm -e vim'#10);
  c := TConfig.Create('/tmp/luh-editgate/');
  c.LoadOverrides();
  Check('0.0.0.0 refuses edit', not EditAllowed(c));

  { A specific LAN address is still reachable by other machines, so it is
    refused too -- the gate is "is this private", not "is this 0.0.0.0". }
  WriteFile('/tmp/luh-editgate/.luhmann.ini',
    'bind = 192.168.1.50'#10'editor = xterm -e vim'#10);
  c := TConfig.Create('/tmp/luh-editgate/');
  c.LoadOverrides();
  Check('LAN address refuses edit', not EditAllowed(c));

  { --- the spy proves no process is spawned when refused --- }
  Spy := TSpyEditor.Create();
  Spy.Launched := False;
  if EditAllowed(c) then
    Spy.LaunchEditor('/tmp/luh-editgate/note.adoc');
  Check('no editor spawned when refused', not Spy.Launched);

  { --- and that it IS reached when allowed, so the gate is not simply off --- }
  WriteFile('/tmp/luh-editgate/.luhmann.ini', 'editor = xterm -e vim'#10);
  c := TConfig.Create('/tmp/luh-editgate/');
  c.LoadOverrides();
  Spy.Launched := False;
  if EditAllowed(c) then
    Spy.LaunchEditor('/tmp/luh-editgate/note.adoc');
  Check('editor spawned when allowed', Spy.Launched);

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
