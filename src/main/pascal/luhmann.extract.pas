{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.extract - pure scanners that pull structure out of AsciiDoc source:
  the document title, the tag set, and the outbound note references.  No I/O;
  operates purely on the source string, so it is exhaustively unit-testable.

  Reference forms recognised:
    xref:fruit/apple.adoc[Apple]   - block/inline cross reference
    link:fruit/apple.adoc[Apple]   - link macro to a local .adoc
  Tag forms recognised:
    :tags: fruit, pome, edible      - document attribute (canonical)
    #hashtag                        - inline, outside delimited blocks
}
unit Luhmann.Extract;

interface

uses
  Generics.Collections;

{ First level-0 title ('= Title') found, or '' if none. }
function ExtractTitle(const ASource: string): string;

{ Tags declared via ':tags:'. Lower-cased, de-duplicated, insertion order
  preserved. Caller owns the returned list. }
function ExtractTags(const ASource: string): TList<string>;

{ Outbound note references (xref: / link: targets ending in .adoc), normalised
  relative to ABaseDir (the directory of the referencing note). Caller owns the
  returned list. }
function ExtractOutLinks(const ASource, ABaseDir: string): TList<string>;

{ Normalise a possibly-relative reference target against a base directory,
  collapsing '.' and '..' segments. Exposed for testing. }
function NormaliseRef(const ABaseDir, ATarget: string): string;

implementation

uses
  StrUtils, Luhmann.Util;

function ExtractTitle(const ASource: string): string;
var
  Lines: TList<string>;
  I: Integer;
  Ln: string;
begin
  Result := '';
  Lines := SplitLines(ASource);
  for I := 0 to Lines.Count - 1 do
  begin
    Ln := TrimStr(Lines.Get(I));
    if StartsStr('= ', Ln) then
    begin
      Result := TrimStr(Copy(Ln, 2, Length(Ln) - 2));
      Break;
    end;
  end;
end;

function ExtractTags(const ASource: string): TList<string>;
var
  Lines: TList<string>;
  Parts: TList<string>;
  I, J: Integer;
  Ln, Rest, Tag: string;
begin
  Result := TList<string>.Create();
  Lines := SplitLines(ASource);
  for I := 0 to Lines.Count - 1 do
  begin
    Ln := TrimStr(Lines.Get(I));
    if StartsText(':tags:', Ln) then
    begin
      Rest := TrimStr(Copy(Ln, 6, Length(Ln) - 6));
      Parts := SplitChar(Rest, CH_COMMA);
      for J := 0 to Parts.Count - 1 do
      begin
        Tag := LowerStr(TrimStr(Parts.Get(J)));
        if (Tag <> '') and (Result.IndexOf(Tag) < 0) then
          Result.Add(Tag);
      end;
    end;
  end;
  { The :tags: attribute is the canonical, unambiguous form. Inline hashtags
    can be added later without changing this contract. }
end;

function NormaliseRef(const ABaseDir, ATarget: string): string;
var
  Combined: string;
  Segs: TList<string>;
  Outp: TList<string>;
  I: Integer;
  Seg: string;
begin
  if StartsStr('/', ATarget) then
    Combined := Copy(ATarget, 1, Length(ATarget) - 1)
  else if ABaseDir = '' then
    Combined := ATarget
  else
    Combined := ABaseDir + '/' + ATarget;

  Segs := SplitChar(Combined, CH_SLASH);
  Outp := TList<string>.Create();
  for I := 0 to Segs.Count - 1 do
  begin
    Seg := Segs.Get(I);
    if (Seg = '') or (Seg = '.') then
      Continue
    else if Seg = '..' then
    begin
      if Outp.Count > 0 then
        Outp.Delete(Outp.Count - 1);
    end
    else
      Outp.Add(Seg);
  end;
  Result := JoinList(Outp, '/');
end;

{ Scan for a macro of the form NAME:TARGET[...] starting at byte position
  APos (which must point just past the "NAME:"). Returns the TARGET (up to the
  '[') and sets ANextPos past the macro, or '' if malformed. }
function ReadMacroTarget(const S: string; APos: Integer; var ANextPos: Integer): string;
var
  I, N: Integer;
  Ch: Byte;
begin
  Result := '';
  N := Length(S);
  I := APos;
  while I < N do
  begin
    Ch := Byte(S[I]);
    if Ch = CH_LBRACK then
    begin
      Result := Copy(S, APos, I - APos);
      ANextPos := I + 1;
      Exit;
    end;
    { whitespace before a '[' means this was not a macro }
    if (Ch = 32) or (Ch = 9) or (Ch = 10) or (Ch = 13) then
    begin
      ANextPos := I;
      Exit;
    end;
    I := I + 1;
  end;
  ANextPos := N;
end;

procedure ScanMacro(const ASource, AMacro, ABaseDir: string; AResult: TList<string>);
var
  Pos0, MacroLen, Next: Integer;
  Target, NoteId: string;
begin
  MacroLen := Length(AMacro);
  Pos0 := PosFrom(AMacro, ASource, 0);
  while Pos0 >= 0 do
  begin
    Target := ReadMacroTarget(ASource, Pos0 + MacroLen, Next);
    if EndsText('.adoc', Target) then
    begin
      NoteId := NormaliseRef(ABaseDir, Target);
      if (NoteId <> '') and (AResult.IndexOf(NoteId) < 0) then
        AResult.Add(NoteId);
    end;
    Pos0 := PosFrom(AMacro, ASource, Next);
  end;
end;

function ExtractOutLinks(const ASource, ABaseDir: string): TList<string>;
begin
  Result := TList<string>.Create();
  ScanMacro(ASource, 'xref:', ABaseDir, Result);
  ScanMacro(ASource, 'link:', ABaseDir, Result);
end;

end.
