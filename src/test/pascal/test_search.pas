program search_test;
uses Classes, Luhmann.Model, Luhmann.Ports, Luhmann.Search;
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
  toks: TStringList;
begin
  Pass:=0; Fail:=0;

  WriteLn('plain text: [', HtmlToText('<p>Hello <b>world</b></p>'), ']');
  toks := Tokenise('The quick brown Fox, fox!');
  WriteLn('tokens: ', toks.Count);  // the=stop, quick brown fox fox -> 4 (fox twice)
  toks.Free();

  Impl := TInMemorySearchIndex.Create();
  Idx := Impl;

  n := TNote.Create('fruit/apple.adoc');
  n.Title := 'Apple';
  n.BodyHtml := '<p>An apple is an edible fruit from the apple tree.</p>';
  Idx.Upsert(n); n.Free();

  n := TNote.Create('fruit/orange.adoc');
  n.Title := 'Orange';
  n.BodyHtml := '<p>An orange is a citrus fruit.</p>';
  Idx.Upsert(n); n.Free();

  hits := Idx.Search('apple');
  Check('apple found', hits.Count = 1);
  if hits.Count >= 1 then
  begin
    Check('apple title', hits[0].Title = 'Apple');
    WriteLn('   snippet: ', hits[0].SummaryHtml);
  end;
  hits.Free();

  hits := Idx.Search('fruit');
  Check('fruit in both', hits.Count = 2);
  hits.Free();

  hits := Idx.Search('citrus');
  Check('citrus -> orange only', (hits.Count = 1) and (hits[0].Id = 'fruit/orange.adoc'));
  hits.Free();

  Idx.Remove('fruit/apple.adoc');
  hits := Idx.Search('apple');
  Check('apple gone after remove', hits.Count = 0);
  hits.Free();

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
