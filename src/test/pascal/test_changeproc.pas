program proc_test;
uses Generics.Collections, Luhmann.Model, Luhmann.Ports, Luhmann.ChangeProc;

type
  TFakeRepo = class(INoteRepository)
  public
    Sources: TOrderedDictionary<string, string>;
    constructor Create;
    function ListNoteIds: TList<string>;
    function ReadSource(const AId: string): string;
    function AbsPathOf(const AId: string): string;
    function MtimeOf(const AId: string): Int64;
    function Exists(const AId: string): Boolean;
  end;
  TFakeRenderer = class(IAsciiDocRenderer)
    function Render(const ASource: string): string;
    procedure RenderMany(ASources: TList<string>; AHtmls: TList<string>);
  end;
  TFakeIndex = class(ISearchIndex)
  public
    Upserts, Removes, Clears: Integer;
    procedure Upsert(ANote: TNote);
    procedure Remove(const AId: string);
    procedure Clear;
    function Search(const AQuery: string): TSearchHitList;
  end;
  TCountReload = class(IReloadNotifier)
  public
    Count: Integer;
    procedure NotifyReload;
  end;

constructor TFakeRepo.Create;
begin Sources := TOrderedDictionary<string, string>.Create(); end;
function TFakeRepo.ListNoteIds: TList<string>;
var i: Integer;
begin Result := TList<string>.Create();
  for i := 0 to Sources.Count - 1 do Result.Add(Sources.Keys[i]); end;
function TFakeRepo.ReadSource(const AId: string): string;
begin if not Sources.TryGetValue(AId, Result) then Result := ''; end;
function TFakeRepo.AbsPathOf(const AId: string): string; begin Result := '/n/' + AId; end;
function TFakeRepo.MtimeOf(const AId: string): Int64; begin Result := 1; end;
function TFakeRepo.Exists(const AId: string): Boolean; begin Result := Sources.ContainsKey(AId); end;
function TFakeRenderer.Render(const ASource: string): string;
begin Result := '<body><div id="content">' + ASource + '</div></body>'; end;
procedure TFakeRenderer.RenderMany(ASources: TList<string>; AHtmls: TList<string>);
var i: Integer;
begin
  AHtmls.Clear();
  for i := 0 to ASources.Count - 1 do
    AHtmls.Add(Render(ASources.Get(i)));
end;
procedure TFakeIndex.Upsert(ANote: TNote); begin Upserts := Upserts + 1; end;
procedure TFakeIndex.Remove(const AId: string); begin Removes := Removes + 1; end;
procedure TFakeIndex.Clear; begin Clears := Clears + 1; end;
function TFakeIndex.Search(const AQuery: string): TSearchHitList;
begin Result := TSearchHitList.Create(); end;
procedure TCountReload.NotifyReload; begin Count := Count + 1; end;

var Pass, Fail: Integer;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;

var
  Ports: TPorts;
  RepoImpl: TFakeRepo;
  IdxImpl: TFakeIndex;
  RelImpl: TCountReload;
  Proc: TChangeProcessor;
  bl, tags, notes: TList<string>;
begin
  Pass:=0; Fail:=0;
  RepoImpl := TFakeRepo.Create();
  RepoImpl.Sources.Add('index.adoc',
    '= Home'#10'See xref:fruit/apple.adoc[Apple] and xref:fruit/orange.adoc[Orange].');
  RepoImpl.Sources.Add('fruit/apple.adoc',
    '= Apple'#10':tags: fruit, pome'#10'Link to xref:orange.adoc[Orange].');
  RepoImpl.Sources.Add('fruit/orange.adoc', '= Orange'#10':tags: fruit, citrus');

  IdxImpl := TFakeIndex.Create();
  RelImpl := TCountReload.Create();

  Ports := TPorts.Create();
  Ports.Repo := RepoImpl;
  Ports.Renderer := TFakeRenderer.Create();
  Ports.Index := IdxImpl;
  Ports.Reload := RelImpl;
  Ports.Log := TNullLogger.Create();

  Proc := TChangeProcessor.Create(Ports, 'unfiled');

  Proc.BuildAll();
  Check('index cleared once', IdxImpl.Clears = 1);
  Check('3 upserts', IdxImpl.Upserts = 3);
  Check('title from source', Proc.TitleOf('fruit/apple.adoc') = 'Apple');
  Check('html cached', Proc.HtmlOf('index.adoc') <> '');

  bl := Proc.BacklinkIds('fruit/orange.adoc');
  Check('orange has 2 backlinks', bl.Count = 2);
  tags := Proc.TagsOfNote('fruit/apple.adoc');
  Check('apple tagged fruit+pome', tags.Count = 2);
  notes := Proc.NotesForTag('fruit');
  Check('2 notes tagged fruit', notes.Count = 2);
  Check('index is unfiled', Proc.TagCount('unfiled') = 1);

  Proc.OnDelete('fruit/apple.adoc');
  Check('reload fired on delete', RelImpl.Count = 1);
  bl := Proc.BacklinkIds('fruit/orange.adoc');
  Check('orange backlinks -> 1 after apple delete', bl.Count = 1);
  Check('apple html gone', Proc.HtmlOf('fruit/apple.adoc') = '');

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
