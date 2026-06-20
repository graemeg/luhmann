{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.search - a minimal in-memory full-text index (the Lucene stand-in).
  Tokenises note title + body text into terms, maintains an inverted index
  term -> postings, and answers AND-style queries with TF-based scoring and a
  highlighted snippet.  Deliberately bare-bones, as the brief allows.

  HTML is reduced to plain text before tokenising by dropping everything
  between '<' and '>'.  Tokens are lower-cased maximal runs of ASCII
  alphanumerics; common English stop words are skipped.
}
unit Luhmann.Search;

interface

uses
  Classes,
  Generics.Collections,
  Luhmann.Model,
  Luhmann.Ports;

type
  { Postings for one term: which notes contain it and how often. }
  TPosting = class
  public
    NoteId: string;
    Freq:   Integer;
    constructor Create(const AId: string);
  end;

  TInMemorySearchIndex = class(ISearchIndex)
  private
    { term -> list of TPosting }
    FTerms:  TOrderedDictionary<string, TList<TPosting>>;
    { id -> stored plain-text body (for snippets) }
    FBodies: TOrderedDictionary<string, string>;
    { id -> title }
    FTitles: TOrderedDictionary<string, string>;
    procedure RemovePostingsFor(const AId: string);
    procedure AddTerm(const ATerm, AId: string);
    function Snippet(const ABody: string; AQueryTerms: TStringList): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Upsert(ANote: TNote);
    procedure Remove(const AId: string);
    procedure Clear;
    function Search(const AQuery: string): TSearchHitList;
  end;

{ Reduce HTML to plain text by stripping tags. Exposed for testing. }
function HtmlToText(const AHtml: string): string;

{ Tokenise text into lower-cased alphanumeric terms (stop words removed).
  Caller owns the returned list. }
function Tokenise(const AText: string): TStringList;

implementation

uses
  StrUtils,
  Luhmann.Util;

const
  STOP_WORDS = ',a,an,and,are,as,at,be,by,for,from,in,is,it,of,on,or,the,to,with,';

function IsAlphaNum(B: Byte): Boolean;
begin
  Result := ((B >= 48) and (B <= 57)) or   { 0-9 }
            ((B >= 65) and (B <= 90)) or   { A-Z }
            ((B >= 97) and (B <= 122));    { a-z }
end;

function IsStopWord(const AWord: string): Boolean;
begin
  Result := ContainsStr(STOP_WORDS, ',' + AWord + ',');
end;

function HtmlToText(const AHtml: string): string;
var
  SB: TStringBuilder;
  I, N: Integer;
  InTag: Boolean;
  B: Byte;
begin
  SB := TStringBuilder.Create();
  N := Length(AHtml);
  InTag := False;
  I := 0;
  while I < N do
  begin
    B := Byte(AHtml[I]);
    if B = 60 then          { '<' }
      InTag := True
    else if B = 62 then     { '>' }
    begin
      InTag := False;
      SB.AppendByte(32);    { tag boundary becomes a space }
    end
    else if not InTag then
      SB.AppendByte(B);
    I := I + 1;
  end;
  Result := SB.ToString();
  SB.Free();
end;

function Tokenise(const AText: string): TStringList;
var
  SB: TStringBuilder;
  I, N: Integer;
  B: Byte;
  Tok: string;
begin
  Result := TStringList.Create();
  SB := TStringBuilder.Create();
  N := Length(AText);
  I := 0;
  while I <= N do
  begin
    if (I < N) and IsAlphaNum(Byte(AText[I])) then
      SB.AppendByte(Byte(AText[I]))
    else
    begin
      { word boundary (or end of text): emit the accumulated token }
      if SB.Length > 0 then
      begin
        Tok := LowerStr(SB.ToString());
        SB.Clear();
        if (Length(Tok) > 1) and (not IsStopWord(Tok)) then
          Result.Add(Tok);
      end;
    end;
    I := I + 1;
  end;
  SB.Free();
end;

{ ---- TPosting ---- }

constructor TPosting.Create(const AId: string);
begin
  NoteId := AId;
  Freq := 0;
end;

{ ---- TInMemorySearchIndex ---- }

constructor TInMemorySearchIndex.Create;
begin
  FTerms  := TOrderedDictionary<string, TList<TPosting>>.Create();
  FBodies := TOrderedDictionary<string, string>.Create();
  FTitles := TOrderedDictionary<string, string>.Create();
end;

destructor TInMemorySearchIndex.Destroy;
begin
  Clear();
  FTerms.Free();
  FBodies.Free();
  FTitles.Free();
  inherited Destroy;
end;

procedure TInMemorySearchIndex.Clear;
var
  I, J: Integer;
  Plist: TList<TPosting>;
  P: TPosting;
begin
  for I := 0 to FTerms.Count - 1 do
  begin
    Plist := FTerms.Values[I];
    for J := 0 to Plist.Count - 1 do
    begin
      P := Plist[J];
      P.Free();
    end;
    Plist.Free();
  end;
  FTerms.Free();
  FTerms := TOrderedDictionary<string, TList<TPosting>>.Create();
  { string-valued dicts hold no owned objects; rebuild empty }
  FBodies.Free();
  FBodies := TOrderedDictionary<string, string>.Create();
  FTitles.Free();
  FTitles := TOrderedDictionary<string, string>.Create();
end;

procedure TInMemorySearchIndex.RemovePostingsFor(const AId: string);
var
  I, J: Integer;
  Plist: TList<TPosting>;
  P: TPosting;
begin
  for I := 0 to FTerms.Count - 1 do
  begin
    Plist := FTerms.Values[I];
    J := 0;
    while J < Plist.Count do
    begin
      P := Plist[J];
      if P.NoteId = AId then
      begin
        P.Free();
        Plist.Delete(J);
      end
      else
        J := J + 1;
    end;
  end;
end;

procedure TInMemorySearchIndex.AddTerm(const ATerm, AId: string);
var
  Plist: TList<TPosting>;
  P, Found: TPosting;
  I: Integer;
begin
  if not FTerms.TryGetValue(ATerm, Plist) then
  begin
    Plist := TList<TPosting>.Create();
    FTerms.Add(ATerm, Plist);
  end;
  Found := nil;
  for I := 0 to Plist.Count - 1 do
  begin
    P := Plist[I];
    if P.NoteId = AId then
    begin
      Found := P;
      Break;
    end;
  end;
  if Found = nil then
  begin
    Found := TPosting.Create(AId);
    Plist.Add(Found);
  end;
  Found.Freq := Found.Freq + 1;
end;

procedure TInMemorySearchIndex.Upsert(ANote: TNote);
var
  Text, BodyText: string;
  Toks: TStringList;
  I: Integer;
begin
  RemovePostingsFor(ANote.Id);

  BodyText := HtmlToText(ANote.BodyHtml);
  { Index title terms (weighted by repetition) and body terms. }
  Text := ANote.Title + ' ' + ANote.Title + ' ' + BodyText;
  Toks := Tokenise(Text);
  for I := 0 to Toks.Count - 1 do
    AddTerm(Toks.Get(I), ANote.Id);
  Toks.Free();

  if FBodies.ContainsKey(ANote.Id) then
    FBodies.SetItem(ANote.Id, BodyText)
  else
    FBodies.Add(ANote.Id, BodyText);
  if FTitles.ContainsKey(ANote.Id) then
    FTitles.SetItem(ANote.Id, ANote.Title)
  else
    FTitles.Add(ANote.Id, ANote.Title);
end;

procedure TInMemorySearchIndex.Remove(const AId: string);
begin
  RemovePostingsFor(AId);
  if FBodies.ContainsKey(AId) then
    FBodies.Remove(AId);
  if FTitles.ContainsKey(AId) then
    FTitles.Remove(AId);
end;

function TInMemorySearchIndex.Snippet(const ABody: string;
  AQueryTerms: TStringList): string;
var
  Lower: string;
  I, Pos0, Start, Stop: Integer;
  Term: string;
begin
  Lower := LowerStr(ABody);
  Pos0 := -1;
  { Find the first query term occurrence in the body. }
  for I := 0 to AQueryTerms.Count - 1 do
  begin
    Term := AQueryTerms.Get(I);
    Pos0 := PosFrom(Term, Lower, 0);
    if Pos0 >= 0 then
      Break;
  end;
  if Pos0 < 0 then
  begin
    { No term in body (matched on title only); show the lead. }
    if Length(ABody) > 160 then
      Result := Copy(ABody, 0, 160) + '...'
    else
      Result := ABody;
    Exit;
  end;
  Start := Pos0 - 60;
  if Start < 0 then
    Start := 0;
  Stop := Pos0 + 100;
  if Stop > Length(ABody) then
    Stop := Length(ABody);
  Result := '';
  if Start > 0 then
    Result := '...';
  Result := Result + Copy(ABody, Start, Stop - Start);
  if Stop < Length(ABody) then
    Result := Result + '...';
end;

function TInMemorySearchIndex.Search(const AQuery: string): TSearchHitList;
var
  Terms: TStringList;
  Scores: TOrderedDictionary<string, Integer>;
  I, J, K, Sc, BestIdx, BestScore, IdxTerm: Integer;
  Term, Id, Body, Title: string;
  Plist: TList<TPosting>;
  P: TPosting;
  Cur: Integer;
  Used: TStringList;
  Hit: TSearchHit;
begin
  Result := TSearchHitList.Create();
  Terms := Tokenise(AQuery);
  if Terms.Count = 0 then
  begin
    Terms.Free();
    Exit;
  end;

  { Accumulate a score per note. Each query term matches any indexed term that
    starts with it (prefix search), so 'zet' or 'zet*' finds 'zettelkasten'. A
    trailing '*' on the query term is treated as an explicit wildcard and
    stripped. A full word still matches itself (it is a prefix of itself). }
  Scores := TOrderedDictionary<string, Integer>.Create();
  for I := 0 to Terms.Count - 1 do
  begin
    Term := Terms.Get(I);
    if (Length(Term) > 0) and (Byte(Term[Length(Term) - 1]) = 42) then  { trailing '*' }
      Term := Copy(Term, 0, Length(Term) - 1);
    if Term = '' then
      Continue;
    for IdxTerm := 0 to FTerms.Count - 1 do
      if StartsStr(Term, FTerms.Keys[IdxTerm]) then
      begin
        Plist := FTerms.Values[IdxTerm];
        for J := 0 to Plist.Count - 1 do
        begin
          P := Plist[J];
          if Scores.TryGetValue(P.NoteId, Cur) then
            Scores.SetItem(P.NoteId, Cur + P.Freq)
          else
            Scores.Add(P.NoteId, P.Freq);
        end;
      end;
  end;

  { Selection sort by score descending into the result list (corpora are
    small; a full sort is unnecessary). }
  Used := TStringList.Create();
  for K := 0 to Scores.Count - 1 do
  begin
    BestIdx := -1;
    BestScore := -1;
    for J := 0 to Scores.Count - 1 do
    begin
      Id := Scores.Keys[J];
      if (Used.IndexOf(Id) < 0) and (Scores.Values[J] > BestScore) then
      begin
        BestScore := Scores.Values[J];
        BestIdx := J;
      end;
    end;
    if BestIdx < 0 then
      Break;
    Id := Scores.Keys[BestIdx];
    Used.Add(Id);

    if not FBodies.TryGetValue(Id, Body) then
      Body := '';
    if not FTitles.TryGetValue(Id, Title) then
      Title := Id;

    Hit := TSearchHit.Create();
    Hit.Id := Id;
    Hit.Title := Title;
    Hit.Score := BestScore;
    Hit.SummaryHtml := Snippet(Body, Terms);
    Result.Add(Hit);
  end;

  Used.Free();
  Scores.Free();
  Terms.Free();
end;

end.
