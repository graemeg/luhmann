{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for TChangeProcessor, driven entirely through in-memory fakes
  of the repository, renderer, search index and reload notifier ports. }

unit Luhmann.ChangeProc.Tests;

interface

uses
  blaise.testing, Generics.Collections, Luhmann.Model, Luhmann.Ports,
  Luhmann.ChangeProc;

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

  TChangeProcessorTests = class(TTestCase)
  private
    IdxImpl: TFakeIndex;
    RelImpl: TCountReload;
    Proc: TChangeProcessor;
  protected
    procedure SetUp; override;
  published
    procedure TestBuildAllClearsIndexOnce;
    procedure TestBuildAllUpsertsEveryNote;
    procedure TestTitleFromSource;
    procedure TestHtmlCached;
    procedure TestBacklinks;
    procedure TestTagsOfNote;
    procedure TestNotesForTag;
    procedure TestUntaggedNoteIsUnfiled;
    procedure TestDeleteFiresReload;
    procedure TestDeleteUpdatesBacklinks;
    procedure TestDeleteDropsHtml;
  end;

implementation

{ ---- fakes ---- }

constructor TFakeRepo.Create;
begin
  Sources := TOrderedDictionary<string, string>.Create();
end;

function TFakeRepo.ListNoteIds: TList<string>;
var
  i: Integer;
begin
  Result := TList<string>.Create();
  for i := 0 to Sources.Count - 1 do
    Result.Add(Sources.Keys[i]);
end;

function TFakeRepo.ReadSource(const AId: string): string;
begin
  if not Sources.TryGetValue(AId, Result) then Result := '';
end;

function TFakeRepo.AbsPathOf(const AId: string): string;
begin
  Result := '/n/' + AId;
end;

function TFakeRepo.MtimeOf(const AId: string): Int64;
begin
  Result := 1;
end;

function TFakeRepo.Exists(const AId: string): Boolean;
begin
  Result := Sources.ContainsKey(AId);
end;

function TFakeRenderer.Render(const ASource: string): string;
begin
  Result := '<body><div id="content">' + ASource + '</div></body>';
end;

procedure TFakeRenderer.RenderMany(ASources: TList<string>; AHtmls: TList<string>);
var
  i: Integer;
begin
  AHtmls.Clear();
  for i := 0 to ASources.Count - 1 do
    AHtmls.Add(Render(ASources.Get(i)));
end;

procedure TFakeIndex.Upsert(ANote: TNote); begin Upserts := Upserts + 1; end;
procedure TFakeIndex.Remove(const AId: string); begin Removes := Removes + 1; end;
procedure TFakeIndex.Clear; begin Clears := Clears + 1; end;

function TFakeIndex.Search(const AQuery: string): TSearchHitList;
begin
  Result := TSearchHitList.Create();
end;

procedure TCountReload.NotifyReload; begin Count := Count + 1; end;

{ ---- TChangeProcessorTests ---- }

procedure TChangeProcessorTests.SetUp;
var
  Ports: TPorts;
  RepoImpl: TFakeRepo;
begin
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
end;

procedure TChangeProcessorTests.TestBuildAllClearsIndexOnce;
begin
  AssertEquals('index clears', 1, IdxImpl.Clears);
end;

procedure TChangeProcessorTests.TestBuildAllUpsertsEveryNote;
begin
  AssertEquals('upserts', 3, IdxImpl.Upserts);
end;

procedure TChangeProcessorTests.TestTitleFromSource;
begin
  AssertEquals('title', 'Apple', Proc.TitleOf('fruit/apple.adoc'));
end;

procedure TChangeProcessorTests.TestHtmlCached;
begin
  AssertNotEquals('html cached', '', Proc.HtmlOf('index.adoc'));
end;

procedure TChangeProcessorTests.TestBacklinks;
begin
  AssertEquals('orange backlinks', 2, Proc.BacklinkIds('fruit/orange.adoc').Count);
end;

procedure TChangeProcessorTests.TestTagsOfNote;
begin
  AssertEquals('apple tags', 2, Proc.TagsOfNote('fruit/apple.adoc').Count);
end;

procedure TChangeProcessorTests.TestNotesForTag;
begin
  AssertEquals('notes tagged fruit', 2, Proc.NotesForTag('fruit').Count);
end;

procedure TChangeProcessorTests.TestUntaggedNoteIsUnfiled;
begin
  AssertEquals('unfiled count', 1, Proc.TagCount('unfiled'));
end;

procedure TChangeProcessorTests.TestDeleteFiresReload;
begin
  Proc.OnDelete('fruit/apple.adoc');
  AssertEquals('reloads', 1, RelImpl.Count);
end;

procedure TChangeProcessorTests.TestDeleteUpdatesBacklinks;
begin
  Proc.OnDelete('fruit/apple.adoc');
  AssertEquals('orange backlinks after apple delete', 1,
    Proc.BacklinkIds('fruit/orange.adoc').Count);
end;

procedure TChangeProcessorTests.TestDeleteDropsHtml;
begin
  Proc.OnDelete('fruit/apple.adoc');
  AssertEquals('apple html gone', '', Proc.HtmlOf('fruit/apple.adoc'));
end;

initialization
  RegisterTest(TChangeProcessorTests);

end.
