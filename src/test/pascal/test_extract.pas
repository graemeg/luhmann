program extract_test;
uses Classes, Luhmann.Extract, Luhmann.Util;
var Pass, Fail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
var
  src, baseDir: string;
  tags, links: TStringList;
begin
  Pass:=0; Fail:=0;
  src := '= Apple Title'#10':tags: Fruit, Pome , edible'#10#10'Body text.'#10
       + 'See xref:orange.adoc[Orange] and link:../veg/carrot.adoc[Carrot].'#10
       + 'External xref:fruit/apple.adoc[Apple] from root.';
  baseDir := 'fruit';

  Check('title', ExtractTitle(src) = 'Apple Title');

  tags := ExtractTags(src);
  Check('3 tags', tags.Count = 3);
  Check('lowercased+trimmed', (tags.Get(0)='fruit') and (tags.Get(1)='pome') and (tags.Get(2)='edible'));
  tags.Free();

  links := ExtractOutLinks(src, baseDir);
  WriteLn('  links found: ', links.Count);
  Check('orange resolved', links.IndexOf('fruit/orange.adoc') >= 0);
  Check('carrot via .. resolved', links.IndexOf('veg/carrot.adoc') >= 0);
  links.Free();

  Check('norm simple', NormaliseRef('fruit', 'orange.adoc') = 'fruit/orange.adoc');
  Check('norm ..', NormaliseRef('a/b', '../c.adoc') = 'a/c.adoc');
  Check('norm root base', NormaliseRef('', 'index.adoc') = 'index.adoc');
  Check('norm dot', NormaliseRef('a', './x.adoc') = 'a/x.adoc');

  Check('DirOf nested', DirOf('a/b/c.adoc') = 'a/b');
  Check('DirOf flat', DirOf('x.adoc') = '');

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
