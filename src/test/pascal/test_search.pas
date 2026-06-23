program search_test;
uses Generics.Collections, Luhmann.Model, Luhmann.Ports, Luhmann.Search;
var Pass, Fail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
var
  Idx: ISearchIndex;
  Impl: TInMemorySearchIndex;
  n: TNote;
  hits: TSearchHitList;
  toks: TList<string>;
begin
  Pass:=0; Fail:=0;

  WriteLn('plain text: [', HtmlToText('<p>Hello <b>world</b></p>'), ']');
  toks := Tokenise('The quick brown Fox, fox!');
  WriteLn('tokens: ', toks.Count);  // the=stop, quick brown fox fox -> 4 (fox twice)

  Impl := TInMemorySearchIndex.Create();
  Idx := Impl;

  n := TNote.Create('fruit/apple.adoc');
  n.Title := 'Apple';
  n.BodyHtml := '<p>An apple is an edible fruit from the apple tree.</p>';
  Idx.Upsert(n);

  n := TNote.Create('fruit/orange.adoc');
  n.Title := 'Orange';
  n.BodyHtml := '<p>An orange is a citrus fruit.</p>';
  Idx.Upsert(n);

  hits := Idx.Search('apple');
  Check('apple found', hits.Count = 1);
  if hits.Count >= 1 then
  begin
    Check('apple title', hits[0].Title = 'Apple');
    WriteLn('   snippet: ', hits[0].SummaryHtml);
  end;
  hits := Idx.Search('fruit');
  Check('fruit in both', hits.Count = 2);
  hits := Idx.Search('citrus');
  Check('citrus -> orange only', (hits.Count = 1) and (hits[0].Id = 'fruit/orange.adoc'));
  { Prefix matching: a partial word finds notes containing a word that starts
    with it. 'app' must find Apple (from 'apple'). }
  hits := Idx.Search('app');
  Check('prefix app -> apple', hits.Count = 1);
  { Explicit wildcard '*' behaves like the bare prefix. }
  hits := Idx.Search('cit*');
  Check('wildcard cit* -> orange (citrus)', (hits.Count = 1) and (hits[0].Id = 'fruit/orange.adoc'));
  { A full word still matches itself. }
  hits := Idx.Search('orange');
  Check('full word orange -> orange', (hits.Count = 1) and (hits[0].Id = 'fruit/orange.adoc'));
  { A prefix matching nothing returns no hits. }
  hits := Idx.Search('zzz');
  Check('no match for zzz', hits.Count = 0);
  { Substring opt-in: a leading '*' matches a term anywhere in a word.
    'range' is in the middle/end of 'orange' -> prefix misses, '*range' hits. }
  hits := Idx.Search('range');
  Check('prefix range -> no match', hits.Count = 0);
  hits := Idx.Search('*range');
  Check('substring *range -> orange', (hits.Count = 1) and (hits[0].Id = 'fruit/orange.adoc'));
  Idx.Remove('fruit/apple.adoc');
  hits := Idx.Search('apple');
  Check('apple gone after remove', hits.Count = 0);
  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
