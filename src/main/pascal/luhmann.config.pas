{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.config - configuration, with sensible defaults and an optional
  '.luhmann.ini' override file in the root directory.  A minimal key=value /
  INI reader is used rather than an EDN or YAML parser.

  Recognised keys (all optional):
    port             = 2022
    luhmann-dir      = <root>/.luhmann
    editor           = <command, e.g. nvim-qt>
    catch-all-label  = unfiled
    asciidoctor      = /usr/bin/asciidoctor
}
unit Luhmann.Config;

interface

type
  TConfig = class
  public
    RootDir:    string;
    LuhmannDir: string;
    Port:       Integer;
    Editor:     string;
    CatchAll:   string;
    Asciidoctor: string;
    constructor Create(const ARootDir: string);
    { Apply overrides from '<root>/.luhmann.ini' if it exists. }
    procedure LoadOverrides;
    function SiteDir: string;
    function TempDir: string;
  end;

implementation

uses
  Classes,
  StrUtils,
  Luhmann.Util;

constructor TConfig.Create(const ARootDir: string);
begin
  RootDir := ARootDir;
  { strip a trailing slash }
  if (Length(RootDir) > 0) and (Byte(RootDir[Length(RootDir) - 1]) = CH_SLASH) then
    RootDir := Copy(RootDir, 0, Length(RootDir) - 1);
  LuhmannDir := RootDir + '/.luhmann';
  Port := 2022;
  Editor := '';
  CatchAll := 'unfiled';
  Asciidoctor := '/usr/bin/asciidoctor';
end;

function TConfig.SiteDir: string;
begin
  Result := LuhmannDir + '/site';
end;

function TConfig.TempDir: string;
begin
  Result := LuhmannDir + '/tmp';
end;

function StrToIntDef(const S: string; ADefault: Integer): Integer;
var
  I, N: Integer;
  B: Byte;
  Acc: Integer;
begin
  N := Length(S);
  if N = 0 then
  begin
    Result := ADefault;
    Exit;
  end;
  Acc := 0;
  for I := 0 to N - 1 do
  begin
    B := Byte(S[I]);
    if (B < 48) or (B > 57) then
    begin
      Result := ADefault;
      Exit;
    end;
    Acc := Acc * 10 + (B - 48);
  end;
  Result := Acc;
end;

procedure TConfig.LoadOverrides;
var
  Path, Content, Line, Key, Val: string;
  Lines: TStringList;
  I, Eq: Integer;
begin
  Path := RootDir + '/.luhmann.ini';
  if not FileExists(Path) then
    Exit;
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
    else if Key = 'luhmann-dir' then
      LuhmannDir := Val
    else if Key = 'editor' then
      Editor := Val
    else if Key = 'catch-all-label' then
      CatchAll := Val
    else if Key = 'asciidoctor' then
      Asciidoctor := Val;
  end;
  Lines.Free();
end;

end.
