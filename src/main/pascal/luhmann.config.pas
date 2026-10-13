{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.config - configuration, with sensible defaults and an optional
  '.luhmann.ini' override file in the root directory.  A minimal key=value /
  INI reader is used rather than an EDN or YAML parser.

  Recognised keys (all optional):
    port             = 2022
    bind             = 127.0.0.1
    luhmann-dir      = <root>/.luhmann
    editor           = <command, e.g. nvim-qt>
    catch-all-label  = unfiled
    asciidoctor      = <path; default: first on PATH, else /usr/bin/asciidoctor>

  'bind' is a literal dotted-quad (no DNS): 127.0.0.1 keeps the server private
  to the machine, 0.0.0.0 listens on every interface, and a specific interface
  address (e.g. 192.168.1.50) is narrower than 0.0.0.0 where that is enough.
  It defaults to loopback, so the server is never exposed by accident -- the
  exposure has to be asked for.  An address that does not parse is REJECTED and
  the default is kept, because the failure must not be "fall through to
  0.0.0.0"; call BindIsValid after LoadOverrides to report it.
}
unit Luhmann.Config;

interface

type
  TConfig = class
  public
    RootDir:    string;
    LuhmannDir: string;
    Port:       Integer;
    Bind:       string;    { dotted-quad listen address; 127.0.0.1 by default }
    Editor:     string;
    CatchAll:   string;
    Asciidoctor: string;
    RenderJobs: Integer;   { parallel asciidoctor processes during the build }
    constructor Create(const ARootDir: string);
    { Apply overrides from '<root>/.luhmann.ini' if it exists. Returns True if
      a config file was found and applied, False if defaults were used. }
    function LoadOverrides: Boolean;
    { Absolute path of the config file (whether or not it exists). }
    function ConfigPath: string;
    function SiteDir: string;
    function TempDir: string;
    { Bind as a network-order IPv4, ready for THttpServer.StartOn.  Falls back
      to loopback if Bind does not parse (see BindIsValid). }
    function BindAddr: UInt32;
    { True when Bind is the loopback address.  Features that are safe only on a
      private listener -- launching an editor process, say -- gate on this
      rather than on the string, so '127.0.0.1' and a malformed value that fell
      back to it are treated alike. }
    function BindIsLoopback: Boolean;
    { False when the configured Bind string could not be parsed as a dotted
      quad.  The caller decides whether that is fatal; the value itself has
      already fallen back to loopback. }
    function BindIsValid: Boolean;
    { The asciidoctor executable to run: the configured path when set,
      otherwise the first 'asciidoctor' found on APathList (pass the PATH
      environment value), otherwise /usr/bin/asciidoctor. }
    function ResolveAsciidoctor(const APathList: string): string;
  end;

implementation

uses
  Generics.Collections,
  SysUtils,
  StrUtils,
  Net.Sockets,
  Luhmann.Util;

constructor TConfig.Create(const ARootDir: string);
begin
  RootDir := ARootDir;
  { strip a trailing slash }
  if (Length(RootDir) > 0) and (Byte(RootDir[Length(RootDir) - 1]) = CH_SLASH) then
    RootDir := Copy(RootDir, 0, Length(RootDir) - 1);
  LuhmannDir := RootDir + '/.luhmann';
  Port := 2022;
  Self.Bind := '127.0.0.1';
  Editor := '';
  CatchAll := 'unfiled';
  Asciidoctor := '';   { unset: ResolveAsciidoctor searches PATH }
  RenderJobs := 8;
end;

function TConfig.ResolveAsciidoctor(const APathList: string): string;
begin
  Result := Asciidoctor;
  if Result = '' then
    Result := FindOnPath('asciidoctor', APathList);
  if Result = '' then
    Result := '/usr/bin/asciidoctor';
end;

function TConfig.SiteDir: string;
begin
  Result := LuhmannDir + '/site';
end;

function TConfig.TempDir: string;
begin
  Result := LuhmannDir + '/tmp';
end;

function TConfig.ConfigPath: string;
begin
  Result := RootDir + '/.luhmann.ini';
end;

function TConfig.BindIsValid: Boolean;
var
  Addr: UInt32;
begin
  Result := ParseIPv4(Bind, Addr);
end;

function TConfig.BindAddr: UInt32;
var
  Addr: UInt32;
begin
  if ParseIPv4(Bind, Addr) then
    Result := Addr
  else
    Result := INADDR_LOOPBACK;
end;

function TConfig.BindIsLoopback: Boolean;
begin
  Result := BindAddr() = INADDR_LOOPBACK;
end;

function TConfig.LoadOverrides: Boolean;
var
  Path, Content, Line, Key, Val: string;
  Lines: TList<string>;
  I, Eq: Integer;
begin
  Path := ConfigPath();
  if not FileExists(Path) then
  begin
    Result := False;
    Exit;
  end;
  Content := ReadFile(Path);
  Lines := SplitLines(Content);
  for I := 0 to Lines.Count - 1 do
  begin
    Line := TrimStr(Lines.Get(I));
    if (Line = '') or StartsStr('#', Line) or StartsStr(';', Line) then
      Continue;
    Eq := PosFrom('=', Line, 0);
    if Eq < 0 then
      Continue;
    Key := LowerStr(TrimStr(Copy(Line, 0, Eq)));
    Val := TrimStr(Copy(Line, Eq + 1, Length(Line) - Eq - 1));
    if Key = 'port' then
      Port := StrToIntDef(Val, Port)
    else if Key = 'bind' then
      { Stored as given -- including an unparseable value, so BindIsValid can
        report it and the caller can refuse to start.  BindAddr still resolves
        to loopback meanwhile, so no malformed value can widen exposure. }
      Self.Bind := Val
    else if Key = 'luhmann-dir' then
      LuhmannDir := Val
    else if Key = 'editor' then
      Editor := Val
    else if Key = 'catch-all-label' then
      CatchAll := Val
    else if Key = 'asciidoctor' then
      Asciidoctor := Val
    else if Key = 'render-jobs' then
      RenderJobs := StrToIntDef(Val, RenderJobs);
  end;
  Result := True;
end;

end.
