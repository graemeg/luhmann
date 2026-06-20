program adapt_test;
uses Classes, Luhmann.Model, Luhmann.Ports, Luhmann.Adapters;
var
  Repo: INoteRepository;
  Rend: IAsciiDocRenderer;
  Log: ILogger;
  ids: TStringList;
  i: Integer;
  src, html: string;
begin
  Log := TConsoleLogger.Create();
  Log.Info('adapter test start');

  Repo := TFilesystemNoteRepository.Create('/data/devel/luhmann/example');
  ids := Repo.ListNoteIds();
  WriteLn('notes found: ', ids.Count);
  for i := 0 to ids.Count - 1 do
    WriteLn('  id: ', ids.Get(i));

  src := Repo.ReadSource('index.adoc');
  WriteLn('index source len: ', Length(src));
  WriteLn('index abspath: ', Repo.AbsPathOf('index.adoc'));
  WriteLn('index mtime>0: ', Repo.MtimeOf('index.adoc') > 0);

  Rend := TAsciidoctorRenderer.Create('', '/tmp/luh-render');
  html := Rend.Render(src);
  WriteLn('--- rendered index.adoc body ---');
  WriteLn(html);

  ids.Free();
end.
