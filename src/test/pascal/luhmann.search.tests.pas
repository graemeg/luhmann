{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for the in-memory search index: tokenising, whole-word,
  prefix, wildcard and substring matching, and removal. }

unit Luhmann.Search.Tests;

interface

uses
  blaise.testing, Luhmann.Ports;

type
  TSearchIndexTests = class(TTestCase)
  private
    Idx: ISearchIndex;
    procedure AssertSingleHit(const AMsg, AQuery, AExpectedId: string);
  protected
    procedure SetUp; override;
  published
    procedure TestHtmlToText;
    procedure TestTokeniseDropsStopWords;
    procedure TestWholeWord;
    procedure TestWordInBothNotes;
    procedure TestPrefix;
    procedure TestWildcardSuffix;
    procedure TestFullWordMatchesItself;
    procedure TestNoMatch;
    procedure TestPrefixDoesNotMatchMidWord;
    procedure TestLeadingWildcardMatchesSubstring;
    procedure TestRemove;
  end;

implementation

uses
  Generics.Collections, Luhmann.Model, Luhmann.Search;

procedure TSearchIndexTests.SetUp;
var
  n: TNote;
begin
  Idx := TInMemorySearchIndex.Create();

  n := TNote.Create('fruit/apple.adoc');
  n.Title := 'Apple';
  n.BodyHtml := '<p>An apple is an edible fruit from the apple tree.</p>';
  Idx.Upsert(n);

  n := TNote.Create('fruit/orange.adoc');
  n.Title := 'Orange';
  n.BodyHtml := '<p>An orange is a citrus fruit.</p>';
  Idx.Upsert(n);
end;

procedure TSearchIndexTests.AssertSingleHit(const AMsg, AQuery, AExpectedId: string);
var
  hits: TSearchHitList;
begin
  hits := Idx.Search(AQuery);
  AssertEquals(AMsg + ' (hit count)', 1, hits.Count);
  AssertEquals(AMsg + ' (hit id)', AExpectedId, hits[0].Id);
end;

procedure TSearchIndexTests.TestHtmlToText;
var
  text: string;
begin
  text := HtmlToText('<p>Hello <b>world</b></p>');
  AssertContains('keeps text', 'world', text);
  AssertTrue('drops tags', Pos('<', text) < 0);
end;

{ 'the' is a stop word; quick, brown, fox, fox remain. }
procedure TSearchIndexTests.TestTokeniseDropsStopWords;
begin
  AssertEquals('token count', 4, Tokenise('The quick brown Fox, fox!').Count);
end;

procedure TSearchIndexTests.TestWholeWord;
var
  hits: TSearchHitList;
begin
  hits := Idx.Search('apple');
  AssertEquals('apple hits', 1, hits.Count);
  AssertEquals('apple title', 'Apple', hits[0].Title);
end;

procedure TSearchIndexTests.TestWordInBothNotes;
begin
  AssertEquals('fruit hits', 2, Idx.Search('fruit').Count);
end;

{ A partial word finds notes containing a word that starts with it. }
procedure TSearchIndexTests.TestPrefix;
begin
  AssertSingleHit('prefix app', 'app', 'fruit/apple.adoc');
end;

{ An explicit trailing '*' behaves like the bare prefix. }
procedure TSearchIndexTests.TestWildcardSuffix;
begin
  AssertSingleHit('wildcard cit*', 'cit*', 'fruit/orange.adoc');
end;

procedure TSearchIndexTests.TestFullWordMatchesItself;
begin
  AssertSingleHit('full word orange', 'orange', 'fruit/orange.adoc');
end;

procedure TSearchIndexTests.TestNoMatch;
begin
  AssertEquals('zzz hits', 0, Idx.Search('zzz').Count);
end;

{ 'range' sits in the middle of 'orange', so a plain prefix search misses. }
procedure TSearchIndexTests.TestPrefixDoesNotMatchMidWord;
begin
  AssertEquals('range hits', 0, Idx.Search('range').Count);
end;

{ Substring opt-in: a leading '*' matches the term anywhere in a word. }
procedure TSearchIndexTests.TestLeadingWildcardMatchesSubstring;
begin
  AssertSingleHit('substring *range', '*range', 'fruit/orange.adoc');
end;

procedure TSearchIndexTests.TestRemove;
begin
  Idx.Remove('fruit/apple.adoc');
  AssertEquals('apple hits after remove', 0, Idx.Search('apple').Count);
end;

initialization
  RegisterTest(TSearchIndexTests);

end.
