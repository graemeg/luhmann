{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.json - a minimal JSON writer.  Only emission is needed (every API
  input arrives as a query parameter, never a request body), so there is no
  reader.  TJsonWriter accumulates a document with correct string escaping.
}
unit Luhmann.Json;

interface

uses
  Classes;

type
  TJsonWriter = class
  private
    FSB: TStringBuilder;
    FNeedComma: Boolean;
    procedure Sep;
  public
    constructor Create;
    destructor Destroy; override;

    procedure BeginObject;
    procedure EndObject;
    procedure BeginArray;
    procedure EndArray;

    { Begin a named member whose value follows (object context). }
    procedure Key(const AName: string);

    { Scalar values (usable as array elements or after Key). }
    procedure StrValue(const AValue: string);
    procedure IntValue(AValue: Integer);
    procedure BoolValue(AValue: Boolean);

    { Convenience: "name": "value" member. }
    procedure StrField(const AName, AValue: string);
    procedure IntField(const AName: string; AValue: Integer);

    function ToString: string; override;
  end;

{ Escape a string as a JSON string literal contents (no surrounding quotes). }
function JsonEscape(const S: string): string;

implementation

function JsonEscape(const S: string): string;
var
  SB: TStringBuilder;
  I, N: Integer;
  B: Byte;
begin
  SB := TStringBuilder.Create();
  N := Length(S);
  I := 0;
  while I < N do
  begin
    B := Byte(S[I]);
    if B = 34 then SB.Append('\"')        { " }
    else if B = 92 then SB.Append('\\')   { \ }
    else if B = 10 then SB.Append('\n')
    else if B = 13 then SB.Append('\r')
    else if B = 9 then SB.Append('\t')
    else if B < 32 then SB.Append(' ')    { other control chars -> space }
    else SB.AppendByte(B);
    I := I + 1;
  end;
  Result := SB.ToString();
  SB.Free();
end;

constructor TJsonWriter.Create;
begin
  FSB := TStringBuilder.Create();
  FNeedComma := False;
end;

destructor TJsonWriter.Destroy;
begin
  FSB.Free();
  inherited Destroy;
end;

procedure TJsonWriter.Sep;
begin
  if FNeedComma then
    FSB.Append(',');
  FNeedComma := False;
end;

procedure TJsonWriter.BeginObject;
begin
  Sep();
  FSB.Append('{');
end;

procedure TJsonWriter.EndObject;
begin
  FSB.Append('}');
  FNeedComma := True;
end;

procedure TJsonWriter.BeginArray;
begin
  Sep();
  FSB.Append('[');
end;

procedure TJsonWriter.EndArray;
begin
  FSB.Append(']');
  FNeedComma := True;
end;

procedure TJsonWriter.Key(const AName: string);
begin
  Sep();
  FSB.Append('"');
  FSB.Append(JsonEscape(AName));
  FSB.Append('":');
  FNeedComma := False;
end;

procedure TJsonWriter.StrValue(const AValue: string);
begin
  Sep();
  FSB.Append('"');
  FSB.Append(JsonEscape(AValue));
  FSB.Append('"');
  FNeedComma := True;
end;

procedure TJsonWriter.IntValue(AValue: Integer);
begin
  Sep();
  FSB.Append(IntToStr(AValue));
  FNeedComma := True;
end;

procedure TJsonWriter.BoolValue(AValue: Boolean);
begin
  Sep();
  if AValue then
    FSB.Append('true')
  else
    FSB.Append('false');
  FNeedComma := True;
end;

procedure TJsonWriter.StrField(const AName, AValue: string);
begin
  Key(AName);
  StrValue(AValue);
end;

procedure TJsonWriter.IntField(const AName: string; AValue: Integer);
begin
  Key(AName);
  IntValue(AValue);
end;

function TJsonWriter.ToString: string;
begin
  Result := FSB.ToString();
end;

end.
