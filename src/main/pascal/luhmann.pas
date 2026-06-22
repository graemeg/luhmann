{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann - the composition root and program entry point.  Wires the concrete
  adapters to the ports, performs the initial build, then runs a single-thread
  event loop that interleaves non-blocking HTTP serving with filesystem polling
  for live reload.

  Usage:  luhmann <root-dir>
}
program Luhmann;

uses
  Classes,
  Luhmann.Util,
  Net.Sockets,
  Luhmann.Ports,
  Luhmann.Model,
  Luhmann.Config,
  Luhmann.Adapters,
  Luhmann.Search,
  Luhmann.ChangeProc,
  Luhmann.Watch,
  Net.Http.Server,
  Luhmann.App;

type
  { Reload notifier that drives the HTTP server's websocket broadcast. The
    server is held as a separate object field (calling a method on a held
    object is safe, unlike calling through a Self-owned interface field). }
  TServerReloadNotifier = class(IReloadNotifier)
  private
    FServer: THttpServer;
  public
    constructor Create(AServer: THttpServer);
    procedure NotifyReload;
  end;

constructor TServerReloadNotifier.Create(AServer: THttpServer);
begin
  FServer := AServer;
end;

procedure TServerReloadNotifier.NotifyReload;
begin
  FServer.Broadcast('reload');
end;

procedure ApplyChanges(AProc: TChangeProcessor; ACS: TChangeSet);
var
  I: Integer;
begin
  for I := 0 to ACS.Created.Count - 1 do
    AProc.OnUpsert(ACS.Created.Get(I));
  for I := 0 to ACS.Modified.Count - 1 do
    AProc.OnUpsert(ACS.Modified.Get(I));
  for I := 0 to ACS.Deleted.Count - 1 do
    AProc.OnDelete(ACS.Deleted.Get(I));
end;

var
  RootDir, PublicDir: string;
  Config: TConfig;
  Ports: TPorts;
  Proc: TChangeProcessor;
  Watcher: TPollingWatcher;
  Server: THttpServer;
  App: TLuhmannApp;
  Handler: IRequestHandler;
  CS: TChangeSet;
  PollCounter: Integer;
  HadConfig: Boolean;

begin
  { Never let a write to a closed browser socket kill us with SIGPIPE. }
  IgnoreSigPipe();

  if ParamCount() < 1 then
  begin
    WriteLn('Usage: luhmann <root-dir>');
    Halt(1);
  end;
  RootDir := ParamStr(1);
  if not DirectoryExists(RootDir) then
  begin
    WriteLn('Directory does not exist: ', RootDir);
    Halt(1);
  end;

  { Resolve where static assets live. Priority:
      1. LUHMANN_PUBLIC env var (explicit override)
      2. 'public' beside the running binary (the PasBuild layout: target/public)
      3. the in-repo source resources (dev convenience) }
  PublicDir := GetEnvVar('LUHMANN_PUBLIC');
  if PublicDir = '' then
  begin
    PublicDir := DirOf(ParamStr(0)) + '/public';
    if not DirectoryExists(PublicDir) then
      PublicDir := 'src/main/resources/public';
  end;

  Config := TConfig.Create(RootDir);
  HadConfig := Config.LoadOverrides();
  ForceDirectories(Config.TempDir());

  WriteLn('Luhmann starting');
  WriteLn('  root:        ', Config.RootDir);
  if HadConfig then
    WriteLn('  config:      ', Config.ConfigPath())
  else
    WriteLn('  config:      none found at ', Config.ConfigPath(),
            ' (using defaults)');
  WriteLn('  port:        ', Config.Port);
  WriteLn('  render-jobs: ', Config.RenderJobs);
  WriteLn('  public:      ', PublicDir);

  { --- compose adapters into the port registry --- }
  Ports := TPorts.Create();
  Ports.Repo     := TFilesystemNoteRepository.Create(Config.RootDir);
  Ports.Renderer := TAsciidoctorRenderer.Create(Config.Asciidoctor,
                      Config.TempDir(), Config.RenderJobs);
  Ports.Index    := TInMemorySearchIndex.Create();
  Ports.Editor   := TProcessEditorLauncher.Create(Config.Editor);
  Ports.Log      := TConsoleLogger.Create();

  { --- core --- }
  Proc := TChangeProcessor.Create(Ports, Config.CatchAll);

  { --- HTTP server (created before the reload notifier needs it) --- }
  Server := THttpServer.Create(Config.Port);
  if not Server.Start() then
  begin
    WriteLn('Failed to bind port ', Config.Port);
    Halt(1);
  end;
  Server.SetNonBlocking();
  Ports.Reload := TServerReloadNotifier.Create(Server);

  { --- initial build --- }
  Proc.BuildAll();

  { --- watcher --- }
  Watcher := TPollingWatcher.Create(Ports);
  Watcher.Prime();

  App := TLuhmannApp.Create(Proc, Config, Ports, PublicDir);
  Handler := App;

  WriteLn('Luhmann ready at http://localhost:', Config.Port);

  { --- event loop: serve any pending request, else poll for changes --- }
  PollCounter := 0;
  while True do
  begin
    if not Server.PollOnce(Handler) then
    begin
      { No connection waiting. Poll the filesystem roughly every ~500ms
        (10 idle iterations of 50ms) to keep CPU low. }
      Sleep(50);
      PollCounter := PollCounter + 1;
      if PollCounter >= 10 then
      begin
        PollCounter := 0;
        CS := Watcher.Poll();
        if not CS.IsEmpty() then
          ApplyChanges(Proc, CS);
        CS.Free();
      end;
    end;
  end;
end.
