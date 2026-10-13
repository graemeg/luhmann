{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.util - small pure string/path helpers used across the core and
  adapters.  String lists cross boundaries as TList<string>.
}
unit Luhmann.Util;

interface

uses
  Generics.Collections;

const
  { ASCII byte constants. NB: Byte('x') on a char *literal* does NOT yield the
    character code in this compiler (a literal is a UTF-8 string and the cast
    takes the pointer), so byte comparisons must use numeric constants. A byte
    read FROM a string via S[i] does give the correct code. }
  CH_TAB    = 9;
  CH_LF     = 10;
  CH_CR     = 13;
  CH_SPACE  = 32;
  CH_COMMA  = 44;
  CH_SLASH  = 47;
  CH_COLON  = 58;
  CH_LBRACK = 91;   { [ }

{ Trim leading/trailing ASCII whitespace. }
function TrimStr(const S: string): string;

{ Lower-case (ASCII). }
function LowerStr(const S: string): string;

{ 0-based index of ASub in S at or after AFrom, or -1 if not found. }
function PosFrom(const ASub, S: string; AFrom: Integer): Integer;

{ SplitChar / SplitLines / JoinList now live in the stdlib StrUtils unit. }

{ Directory portion of a relative path: 'a/b/c.adoc' -> 'a/b'; 'x.adoc' -> ''. }
function DirOf(const APath: string): string;

{ Read an entire file as raw bytes, null-bytes preserved (unlike ReadFile,
  which is text-oriented and stops at the first null). Suitable for binary
  assets such as images. Returns '' if the file cannot be opened. }
function ReadBinaryFile(const APath: string): string;

{ Full path of the first file named AName in the colon-separated directory
  list APathList (a PATH value), or '' if none matches.  Empty entries are
  skipped rather than treated as the current directory. }
function FindOnPath(const AName, APathList: string): string;

implementation

uses
  StrUtils, SysUtils, Streams;

function TrimStr(const S: string): string;
begin
  Result := Trim(S);
end;

function LowerStr(const S: string): string;
begin
  Result := LowerCase(S);
end;

function PosFrom(const ASub, S: string; AFrom: Integer): Integer;
begin
  if AFrom < 0 then
    AFrom := 0;
  Result := PosEx(ASub, S, AFrom);
end;

function DirOf(const APath: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Length(APath) - 1 downto 0 do
    if Byte(APath[I]) = CH_SLASH then
    begin
      Result := Copy(APath, 0, I);
      Exit;
    end;
end;

function ReadBinaryFile(const APath: string): string;
var
  Stream: TFileInputStream;
  SB: TStringBuilder;
  Buf: array[0..8191] of Byte;
  N, I: Integer;
begin
  Result := '';
  if not FileExists(APath) then
    Exit;
  Stream := TFileInputStream.Create(APath);
  SB := TStringBuilder.Create();
  repeat
    N := Stream.Read(@Buf[0], 8192);
    for I := 0 to N - 1 do
      SB.AppendByte(Buf[I]);
  until N <= 0;
  Result := SB.ToString();
  Stream.Close();
end;

function FindOnPath(const AName, APathList: string): string;
var
  Dirs: TList<string>;
  I: Integer;
  Dir: string;
begin
  Result := '';
  Dirs := SplitChar(APathList, CH_COLON);
  for I := 0 to Dirs.Count - 1 do
  begin
    Dir := Dirs.Get(I);
    if Dir = '' then
      Continue;
    if EndsStr('/', Dir) then
      Dir := Copy(Dir, 0, Length(Dir) - 1);
    if FileExists(Dir + '/' + AName) then
    begin
      Result := Dir + '/' + AName;
      Exit;
    end;
  end;
end;

end.
