program core_test;
uses Classes, Luhmann.Graph, Luhmann.TagIndex;

var Pass, Fail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;

function L(const A, B: string): TStringList;
begin
  Result := TStringList.Create();
  if A <> '' then Result.Add(A);
  if B <> '' then Result.Add(B);
end;

var
  G: TLinkGraph;
  T: TTagIndex;
  bl, ot, tags, notes: TStringList;
begin
  Pass:=0; Fail:=0;
  WriteLn('--- LinkGraph ---');
  G := TLinkGraph.Create();
  G.SetOutLinks('index.adoc', L('fruit/apple.adoc', 'fruit/orange.adoc'));
  G.SetOutLinks('fruit/apple.adoc', L('fruit/orange.adoc', ''));

  bl := G.BacklinksOf('fruit/orange.adoc');
  Check('orange has 2 backlinks', bl.Count = 2); bl.Free();
  bl := G.BacklinksOf('fruit/apple.adoc');
  Check('apple 1 backlink (index)', (bl.Count = 1) and (bl.Get(0) = 'index.adoc')); bl.Free();
  ot := G.OutLinksOf('index.adoc');
  Check('index 2 outlinks', ot.Count = 2); ot.Free();

  G.SetOutLinks('fruit/apple.adoc', L('', ''));
  bl := G.BacklinksOf('fruit/orange.adoc');
  Check('orange backlinks -> 1 after apple edit', bl.Count = 1); bl.Free();

  G.RemoveNote('index.adoc');
  bl := G.BacklinksOf('fruit/apple.adoc');
  Check('apple 0 backlinks after index delete', bl.Count = 0); bl.Free();
  G.Free();

  WriteLn('--- TagIndex ---');
  T := TTagIndex.Create('unfiled');
  T.SetTags('fruit/apple.adoc', L('fruit', 'pome'));
  T.SetTags('fruit/orange.adoc', L('fruit', 'citrus'));
  T.SetTags('index.adoc', L('', ''));

  notes := T.NotesWithTag('fruit');
  Check('2 notes tagged fruit', notes.Count = 2); notes.Free();
  notes := T.NotesWithTag('unfiled');
  Check('index is unfiled', (notes.Count = 1) and (notes.Get(0) = 'index.adoc')); notes.Free();
  Check('CountForTag citrus = 1', T.CountForTag('citrus') = 1);
  tags := T.TagsOf('fruit/apple.adoc');
  Check('apple has 2 tags', tags.Count = 2); tags.Free();

  T.SetTags('fruit/apple.adoc', L('fruit', 'edible'));
  Check('pome now empty', T.CountForTag('pome') = 0);
  Check('edible has apple', T.CountForTag('edible') = 1);
  T.RemoveNote('index.adoc');
  Check('unfiled empty after index removed', T.CountForTag('unfiled') = 0);
  T.Free();

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
