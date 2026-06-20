program chrome_test;
uses Classes, Luhmann.Chrome;
var Pass, Fail: Integer; page: string; ids, titles, tags: TStringList;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
begin
  Pass:=0; Fail:=0;
  Check('escape', HtmlEscape('a<b>&"x') = 'a&lt;b&gt;&amp;&quot;x');
  Check('noteurl', NoteUrl('fruit/apple.adoc') = '/fruit/apple.html');

  ids := TStringList.Create(); ids.Add('index.adoc'); ids.Add('fruit/pear.adoc');
  titles := TStringList.Create(); titles.Add('Home'); titles.Add('Pear');
  tags := TStringList.Create(); tags.Add('fruit'); tags.Add('pome');

  page := RenderPage('Apple', '<p>An apple.</p>', ids, titles, tags);
  Check('has doctype', Pos('<!DOCTYPE html>', page) >= 0);
  Check('has title', Pos('<title>Apple</title>', page) >= 0);
  Check('has body content', Pos('<p>An apple.</p>', page) >= 0);
  Check('has backlinks header', Pos('Backlinks', page) >= 0);
  Check('backlink to index', Pos('href="/index.html"', page) >= 0);
  Check('backlink to pear', Pos('href="/fruit/pear.html"', page) >= 0);
  Check('tag chip', Pos('#fruit', page) >= 0);
  Check('css link', Pos('/luhmann.css', page) >= 0);
  Check('js script', Pos('/luhmann.js', page) >= 0);

  ids.Free(); titles.Free(); tags.Free();

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
