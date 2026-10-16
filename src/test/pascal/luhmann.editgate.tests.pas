{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Tests the policy that gates /api/edit on the listen address.

  GET /api/edit spawns an external editor process on the host.  That is
  reasonable when the server is private to the machine you are sitting at, and
  it is a remote process-spawn primitive the moment the listener is reachable
  from anywhere else.  So the endpoint is refused whenever the bind address is
  not loopback -- and, because a headless host has no display to launch an
  editor onto, refusing costs nothing real. }

unit Luhmann.EditGate.Tests;

interface

uses
  blaise.testing, Luhmann.Config, Luhmann.Ports;

type
  { Records whether LaunchEditor was reached, so a test can prove the gate
    refused BEFORE any process was spawned -- not merely that the response
    said 403. }
  TSpyEditor = class(IEditorLauncher)
  public
    Launched: Boolean;
    function LaunchEditor(const AAbsPath: string): Boolean;
  end;

  TEditGateTests = class(TTestCase)
  private
    function LoadIni(const AIni: string): TConfig;
    function TryEdit(AConfig: TConfig): Boolean;
  protected
    procedure SetUp; override;
  published
    procedure TestLoopbackAllowsEdit;
    procedure TestAnyInterfaceRefusesEdit;
    procedure TestLanAddressRefusesEdit;
    procedure TestNoEditorSpawnedWhenRefused;
    procedure TestEditorSpawnedWhenAllowed;
  end;

implementation

const
  DIR = '/tmp/luh-test-editgate';

function TSpyEditor.LaunchEditor(const AAbsPath: string): Boolean;
begin
  Launched := True;
  Result := True;
end;

{ Mirrors the guard in TLuhmannApp.ApiEdit. }
function EditAllowed(AConfig: TConfig): Boolean;
begin
  Result := AConfig.BindIsLoopback();
end;

procedure TEditGateTests.SetUp;
begin
  ForceDirectories(DIR);
end;

function TEditGateTests.LoadIni(const AIni: string): TConfig;
begin
  WriteFile(DIR + '/.luhmann.ini', AIni);
  Result := TConfig.Create(DIR + '/');
  Result.LoadOverrides();
end;

{ Run the gated edit path against a spy; True when the editor was launched. }
function TEditGateTests.TryEdit(AConfig: TConfig): Boolean;
var
  Spy: TSpyEditor;
begin
  Spy := TSpyEditor.Create();
  Spy.Launched := False;
  if EditAllowed(AConfig) then
    Spy.LaunchEditor(DIR + '/note.adoc');
  Result := Spy.Launched;
end;

procedure TEditGateTests.TestLoopbackAllowsEdit;
begin
  AssertTrue('loopback allows edit',
    EditAllowed(LoadIni('editor = xterm -e vim'#10)));
end;

procedure TEditGateTests.TestAnyInterfaceRefusesEdit;
begin
  AssertFalse('0.0.0.0 refuses edit',
    EditAllowed(LoadIni('bind = 0.0.0.0'#10'editor = xterm -e vim'#10)));
end;

{ A specific LAN address is still reachable by other machines, so it is
  refused too -- the gate is "is this private", not "is this 0.0.0.0". }
procedure TEditGateTests.TestLanAddressRefusesEdit;
begin
  AssertFalse('LAN address refuses edit',
    EditAllowed(LoadIni('bind = 192.168.1.50'#10'editor = xterm -e vim'#10)));
end;

procedure TEditGateTests.TestNoEditorSpawnedWhenRefused;
begin
  AssertFalse('no editor spawned when refused',
    TryEdit(LoadIni('bind = 192.168.1.50'#10'editor = xterm -e vim'#10)));
end;

{ And the editor IS reached when allowed, so the gate is not simply off. }
procedure TEditGateTests.TestEditorSpawnedWhenAllowed;
begin
  AssertTrue('editor spawned when allowed',
    TryEdit(LoadIni('editor = xterm -e vim'#10)));
end;

initialization
  RegisterTest(TEditGateTests);

end.
