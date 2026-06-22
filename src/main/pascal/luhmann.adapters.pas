{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.adapters - outbound (driven) adapters that implement the ports using
  concrete technology: the filesystem, the asciidoctor binary, an external
  editor process, and a file/console logger.

  Directory enumeration and AsciiDoc rendering shell out to `find` and
  `asciidoctor` respectively via TProcess, because the runtime exposes neither
  a directory-listing primitive nor an AsciiDoc processor.
}
unit Luhmann.Adapters;

interface

uses
  Classes,
  Luhmann.Model,
  Luhmann.Ports;

type
  { Reads .adoc notes from a root directory on disk. NoteIds are paths relative
    to the root, e.g. 'fruit/apple.adoc'. }
  TFilesystemNoteRepository = class(INoteRepository)
  private
    FRoot: string;   { absolute, no trailing slash }
  public
    constructor Create(const ARoot: string);
    function ListNoteIds: TStringList;
    function ReadSource(const AId: string): string;
    function AbsPathOf(const AId: string): string;
    function MtimeOf(const AId: string): Int64;
    function Exists(const AId: string): Boolean;
  end;

  { Renders AsciiDoc by shelling out to `asciidoctor -s` (embedded body HTML).
    RenderMany launches up to FConcurrency asciidoctor processes at once for a
    much faster initial build. }
  TAsciidoctorRenderer = class(IAsciiDocRenderer)
  private
    FExe:         string;
    FTempDir:     string;
    FConcurrency: Integer;
    function RenderFile(const ATempFile: string): string;
  public
    constructor Create(const AExe, ATempDir: string; AConcurrency: Integer);
    function Render(const ASource: string): string;
    procedure RenderMany(ASources: TStringList; AHtmls: TStringList);
  end;

  { Launches an external editor as a detached process. }
  TProcessEditorLauncher = class(IEditorLauncher)
  private
    FCommand: string;   { e.g. 'nvim-qt' or 'code -g' }
  public
    constructor Create(const ACommand: string);
    function LaunchEditor(const AAbsPath: string): Boolean;
  end;

  { Levelled logger writing timestamped lines to stderr (fd 2). Minimal by
    design; a file sink can be added later behind the same ILogger port. }
  TConsoleLogger = class(ILogger)
  public
    procedure Info(const AMsg: string);
    procedure Error(const AMsg: string);
  end;

implementation

uses
  StrUtils,
  Generics.Collections,
  Process,
  Luhmann.Util;

{ The logger writes diagnostic lines to stderr (fd 2). That is process I/O, not
  networking, so it uses a local write(2) binding rather than Net.Sockets. }
function c_write(AFd: Integer; ABuf: Pointer; ACount: Int64): Int64;
  external name 'write';

{ ---- helpers ---- }

function RunCapture(const AExe: string; AArgs: TStringList): string;
var
  P: TProcess;
  I: Integer;
  Chunk: string;
  SB: TStringBuilder;
begin
  P := TProcess.Create(nil);
  P.Executable := AExe;
  for I := 0 to AArgs.Count - 1 do
    P.Parameters.Add(AArgs.Get(I));
  P.Execute();

  { Drain the child's stdout pipe in a loop. ReadOutput returns at most one
    pipe-buffer chunk and '' at EOF, so a single read truncates large output
    and reading only AFTER WaitOnExit deadlocks when the child fills the pipe
    (~64 KB) before exiting. Read until EOF first, then reap. }
  SB := TStringBuilder.Create();
  while True do
  begin
    Chunk := P.ReadOutput();
    if Chunk = '' then
      Break;
    SB.Append(Chunk);
  end;
  P.WaitOnExit();
  Result := SB.ToString();
  SB.Free();
  P.Free();
end;

{ ---- TFilesystemNoteRepository ---- }

constructor TFilesystemNoteRepository.Create(const ARoot: string);
begin
  FRoot := ARoot;
  { drop a trailing slash if present }
  if (Length(FRoot) > 0) and (Byte(FRoot[Length(FRoot) - 1]) = CH_SLASH) then
    FRoot := Copy(FRoot, 0, Length(FRoot) - 1);
end;

function TFilesystemNoteRepository.AbsPathOf(const AId: string): string;
begin
  Result := FRoot + '/' + AId;
end;

function TFilesystemNoteRepository.ListNoteIds: TStringList;
var
  Args, Lines: TStringList;
  Raw, Ln: string;
  I, Prefix: Integer;
begin
  Result := TStringList.Create();
  { find <root> -path <root>/.luhmann -prune -o -type f -name '*.adoc' -print
    The prune skips the derived '.luhmann' directory (site, tmp, index) so the
    renderer's scratch files never masquerade as notes. }
  Args := TStringList.Create();
  Args.Add(FRoot);
  Args.Add('-path');
  Args.Add(FRoot + '/.luhmann');
  Args.Add('-prune');
  Args.Add('-o');
  Args.Add('-type');
  Args.Add('f');
  Args.Add('-name');
  Args.Add('*.adoc');
  Args.Add('-print');
  Raw := RunCapture('/usr/bin/find', Args);
  Args.Free();

  Prefix := Length(FRoot) + 1;   { strip 'FRoot/' to get the relative id }
  Lines := SplitLines(Raw);
  for I := 0 to Lines.Count - 1 do
  begin
    Ln := TrimStr(Lines.Get(I));
    if (Ln <> '') and (Length(Ln) > Prefix) then
      Result.Add(Copy(Ln, Prefix, Length(Ln) - Prefix));
  end;
  Lines.Free();
end;

function TFilesystemNoteRepository.ReadSource(const AId: string): string;
begin
  Result := ReadFile(AbsPathOf(AId));
end;

function TFilesystemNoteRepository.MtimeOf(const AId: string): Int64;
begin
  Result := FileAge(AbsPathOf(AId));
end;

function TFilesystemNoteRepository.Exists(const AId: string): Boolean;
begin
  Result := FileExists(AbsPathOf(AId));
end;

{ ---- TAsciidoctorRenderer ---- }

constructor TAsciidoctorRenderer.Create(const AExe, ATempDir: string;
  AConcurrency: Integer);
begin
  if AExe = '' then
    FExe := '/usr/bin/asciidoctor'
  else
    FExe := AExe;
  FTempDir := ATempDir;
  if AConcurrency < 1 then
    FConcurrency := 1
  else
    FConcurrency := AConcurrency;
  ForceDirectories(FTempDir);
end;

{ Build the asciidoctor argument list for ATempFile. }
procedure BuildRenderArgs(AArgs: TStringList; const ATempFile: string);
begin
  AArgs.Add('-s');           { embedded: body only, no standalone header/footer }
  AArgs.Add('-a');
  AArgs.Add('showtitle');    { keep the document title in the body }
  AArgs.Add(ATempFile);
  AArgs.Add('-o');
  AArgs.Add('-');            { write to stdout }
end;

function TAsciidoctorRenderer.RenderFile(const ATempFile: string): string;
var
  Args: TStringList;
begin
  Args := TStringList.Create();
  BuildRenderArgs(Args, ATempFile);
  Result := RunCapture(FExe, Args);
  Args.Free();
end;

function TAsciidoctorRenderer.Render(const ASource: string): string;
var
  TempFile: string;
begin
  { asciidoctor reads from a file; write the source to a temp file, render to
    stdout in embedded (-s) mode, returning clean body HTML. }
  TempFile := FTempDir + '/render.adoc';
  WriteFile(TempFile, ASource);
  Result := RenderFile(TempFile);
end;

{ Drain a started child process to EOF, then reap it. (Same loop as
  RunCapture, but on an already-launched TProcess.) }
function DrainProcess(P: TProcess): string;
var
  Chunk: string;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create();
  while True do
  begin
    Chunk := P.ReadOutput();
    if Chunk = '' then
      Break;
    SB.Append(Chunk);
  end;
  P.WaitOnExit();
  Result := SB.ToString();
  SB.Free();
end;

procedure TAsciidoctorRenderer.RenderMany(ASources: TStringList;
  AHtmls: TStringList);
var
  N, Base, K, J, SlotFile: Integer;
  Procs: TList<TProcess>;
  P: TProcess;
  TempFile: string;
begin
  AHtmls.Clear();
  N := ASources.Count;
  { Process notes in windows of FConcurrency. Within a window every render
    uses its own temp file (render-<slot>.adoc) so the concurrent writes do
    not clobber one another. All processes in a window run in parallel; we
    then drain them in order, preserving output ordering. }
  Procs := TList<TProcess>.Create();
  Base := 0;
  while Base < N do
  begin
    { launch a window }
    K := 0;
    Procs.Clear();
    while (K < FConcurrency) and (Base + K < N) do
    begin
      SlotFile := K;
      TempFile := FTempDir + '/render-' + IntToStr(SlotFile) + '.adoc';
      WriteFile(TempFile, ASources.Get(Base + K));
      P := TProcess.Create(nil);
      P.Executable := FExe;
      BuildRenderArgs(P.Parameters, TempFile);
      P.Execute();   { returns after fork; child renders concurrently }
      Procs.Add(P);
      K := K + 1;
    end;
    { drain the window in order }
    for J := 0 to Procs.Count - 1 do
    begin
      P := Procs[J];
      AHtmls.Add(DrainProcess(P));
      P.Free();
    end;
    Base := Base + K;
  end;
  Procs.Free();
end;

{ ---- TProcessEditorLauncher ---- }

constructor TProcessEditorLauncher.Create(const ACommand: string);
begin
  FCommand := ACommand;
end;

function TProcessEditorLauncher.LaunchEditor(const AAbsPath: string): Boolean;
var
  Parts: TStringList;
  P: TProcess;
  I: Integer;
begin
  if FCommand = '' then
  begin
    Result := False;
    Exit;
  end;
  { Split the configured command on spaces: first token is the executable,
    the rest are leading arguments, then the note path. }
  Parts := SplitChar(FCommand, CH_SPACE);
  P := TProcess.Create(nil);
  P.Executable := Parts.Get(0);
  for I := 1 to Parts.Count - 1 do
    if Parts.Get(I) <> '' then
      P.Parameters.Add(Parts.Get(I));
  P.Parameters.Add(AAbsPath);
  P.Execute();
  { Do not WaitOnExit: the editor runs independently of the server. }
  P.Free();
  Parts.Free();
  Result := True;
end;

{ ---- TConsoleLogger ---- }

procedure TConsoleLogger.Info(const AMsg: string);
var
  Line: string;
begin
  Line := '[INFO] ' + AMsg + #10;
  c_write(2, PChar(Line), Length(Line));
end;

procedure TConsoleLogger.Error(const AMsg: string);
var
  Line: string;
begin
  Line := '[ERROR] ' + AMsg + #10;
  c_write(2, PChar(Line), Length(Line));
end;

end.
