{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.util - small pure string/path helpers used across the core and
  adapters.  String lists cross boundaries as TStringList (non-generic) because
  free functions cannot return a generic instantiation in this compiler.
}
unit Luhmann.Util;

interface

uses
  Classes;

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
  CH_LBRACK = 91;   { [ }

{ Trim leading/trailing ASCII whitespace. }
function TrimStr(const S: string): string;

{ Lower-case (ASCII). }
function LowerStr(const S: string): string;

{ 0-based index of ASub in S at or after AFrom, or -1 if not found. }
function PosFrom(const ASub, S: string; AFrom: Integer): Integer;

{ Split S into lines on LF, tolerating CRLF (CR stripped). Caller owns. }
function SplitLines(const S: string): TStringList;

{ Split S on a single delimiter byte. Caller owns. }
function SplitChar(const S: string; ADelim: Byte): TStringList;

{ Join a list with ASep between items. }
function JoinList(AList: TStringList; const ASep: string): string;

{ Directory portion of a relative path: 'a/b/c.adoc' -> 'a/b'; 'x.adoc' -> ''. }
function DirOf(const APath: string): string;

implementation

uses
  StrUtils, SysUtils;

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

function StripCR(const S: string): string;
begin
  if (Length(S) > 0) and (Byte(S[Length(S) - 1]) = CH_CR) then
    Result := Copy(S, 0, Length(S) - 1)
  else
    Result := S;
end;

function SplitLines(const S: string): TStringList;
var
  I, N, Start: Integer;
begin
  Result := TStringList.Create();
  N := Length(S);
  Start := 0;
  I := 0;
  while I < N do
  begin
    if Byte(S[I]) = CH_LF then
    begin
      Result.Add(StripCR(Copy(S, Start, I - Start)));
      Start := I + 1;
    end;
    I := I + 1;
  end;
  Result.Add(StripCR(Copy(S, Start, N - Start)));
end;

function SplitChar(const S: string; ADelim: Byte): TStringList;
var
  I, N, Start: Integer;
begin
  Result := TStringList.Create();
  N := Length(S);
  Start := 0;
  I := 0;
  while I < N do
  begin
    if Byte(S[I]) = ADelim then
    begin
      Result.Add(Copy(S, Start, I - Start));
      Start := I + 1;
    end;
    I := I + 1;
  end;
  Result.Add(Copy(S, Start, N - Start));
end;

function JoinList(AList: TStringList; const ASep: string): string;
var
  I: Integer;
begin
  Result := '';
  if AList = nil then
    Exit;
  for I := 0 to AList.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ASep;
    Result := Result + AList.Get(I);
  end;
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

end.
