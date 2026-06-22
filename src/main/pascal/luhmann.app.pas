{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.app - the driving adapter: a single IRequestHandler that routes HTTP
  requests to the domain core and the chrome/JSON renderers.  Holds its
  collaborators through plain object references (TChangeProcessor, TConfig) so
  no interface is stored directly as a field.

  Routes:
    GET /                      -> index.html note page (with chrome + backlinks)
    GET /<path>.html           -> note page
    GET /<asset>               -> static asset from the public dir
    GET /search?q=             -> search results page
    GET /graph                 -> graph visualisation page (static)
    GET /tags , /tags/<tag>    -> tag listing pages
    GET /api/graph?note=&depth -> neighbourhood subgraph JSON
    GET /api/graph/all         -> whole-corpus graph JSON
    GET /api/backlinks?note=   -> backlinks JSON
    GET /api/tags              -> tags + counts JSON
    GET /api/edit?note=        -> launch external editor
}
unit Luhmann.App;

interface

uses
  Classes,
  Net.Http.Server,
  Luhmann.Config,
  Luhmann.ChangeProc,
  Luhmann.Ports;

type
  TLuhmannApp = class(IRequestHandler)
  private
    FProc:      TChangeProcessor;
    FConfig:    TConfig;
    FPorts:     TPorts;
    FPublicDir: string;
    procedure ServeNotePage(const AId: string; AResponse: THttpResponse);
    procedure ServeStatic(const APath: string; AResponse: THttpResponse);
    procedure ServeSearch(ARequest: THttpRequest; AResponse: THttpResponse);
    procedure ServeTagList(const ATag: string; AResponse: THttpResponse);
    procedure ServeAllTags(AResponse: THttpResponse);
    procedure ServeBroken(AResponse: THttpResponse);
    procedure ApiGraph(ARequest: THttpRequest; AResponse: THttpResponse);
    procedure ApiGraphAll(AResponse: THttpResponse);
    procedure ApiBacklinks(ARequest: THttpRequest; AResponse: THttpResponse);
    procedure ApiTags(AResponse: THttpResponse);
    procedure ApiEdit(ARequest: THttpRequest; AResponse: THttpResponse);
    function PathToNoteId(const APath: string): string;
  public
    constructor Create(AProc: TChangeProcessor; AConfig: TConfig;
                       APorts: TPorts; const APublicDir: string);
    procedure Handle(ARequest: THttpRequest; AResponse: THttpResponse);
  end;

implementation

uses
  StrUtils,
  Luhmann.Util,
  Luhmann.Model,
  Luhmann.Chrome,
  Json.Writer;

constructor TLuhmannApp.Create(AProc: TChangeProcessor; AConfig: TConfig;
  APorts: TPorts; const APublicDir: string);
begin
  FProc := AProc;
  FConfig := AConfig;
  FPorts := APorts;
  FPublicDir := APublicDir;
end;

{ Map a request path to a note id: '/' -> index.adoc; '/a/b.html' -> a/b.adoc. }
function TLuhmannApp.PathToNoteId(const APath: string): string;
var
  P: string;
begin
  if (APath = '/') or (APath = '') then
  begin
    Result := 'index.adoc';
    Exit;
  end;
  P := APath;
  if StartsStr('/', P) then
    P := Copy(P, 1, Length(P) - 1);
  if EndsText('.html', P) then
    P := Copy(P, 0, Length(P) - 5) + '.adoc';
  Result := P;
end;

procedure TLuhmannApp.ServeNotePage(const AId: string; AResponse: THttpResponse);
var
  Body, Title: string;
  BacklinkIds, BacklinkTitles, Tags: TStringList;
  I: Integer;
begin
  if not FProc.HasNote(AId) then
  begin
    AResponse.SetText(404, 'text/html; charset=utf-8',
      '<h1>404</h1><p>Note not found: ' + HtmlEscape(AId) + '</p>');
    Exit;
  end;

  Body := FProc.HtmlOf(AId);
  Title := FProc.TitleOf(AId);
  BacklinkIds := FProc.BacklinkIds(AId);
  Tags := FProc.TagsOfNote(AId);

  { Resolve backlink titles. }
  BacklinkTitles := TStringList.Create();
  for I := 0 to BacklinkIds.Count - 1 do
    BacklinkTitles.Add(FProc.TitleOf(BacklinkIds.Get(I)));

  AResponse.SetText(200, 'text/html; charset=utf-8',
    RenderPage(Title, Body, BacklinkIds, BacklinkTitles, Tags));

  BacklinkIds.Free();
  BacklinkTitles.Free();
  Tags.Free();
end;

function ContentTypeFor(const APath: string): string;
begin
  if EndsText('.css', APath) then Result := 'text/css'
  else if EndsText('.js', APath) then Result := 'application/javascript'
  else if EndsText('.svg', APath) then Result := 'image/svg+xml'
  else if EndsText('.html', APath) then Result := 'text/html; charset=utf-8'
  else if EndsText('.json', APath) then Result := 'application/json'
  else if EndsText('.png', APath) then Result := 'image/png'
  else if EndsText('.jpg', APath) then Result := 'image/jpeg'
  else Result := 'application/octet-stream';
end;

procedure TLuhmannApp.ServeStatic(const APath: string; AResponse: THttpResponse);
var
  Rel, FullPath, Content: string;
begin
  Rel := APath;
  if StartsStr('/', Rel) then
    Rel := Copy(Rel, 1, Length(Rel) - 1);
  { reject path traversal }
  if ContainsStr(Rel, '..') then
  begin
    AResponse.SetText(404, 'text/plain', 'not found');
    Exit;
  end;
  { Look for the asset in the bundled public dir first (CSS, JS, favicon,
    cytoscape), then fall back to the notes directory so that images and other
    files living alongside notes (image::apple.jpg) are served too. }
  FullPath := FPublicDir + '/' + Rel;
  if not FileExists(FullPath) then
    FullPath := FConfig.RootDir + '/' + Rel;
  if not FileExists(FullPath) then
  begin
    AResponse.SetText(404, 'text/plain', 'not found');
    Exit;
  end;
  { Read as raw bytes so binary assets (images) are not truncated at the first
    null byte, as a text read would do. }
  Content := ReadBinaryFile(FullPath);
  AResponse.SetText(200, ContentTypeFor(Rel), Content);
end;

procedure TLuhmannApp.ServeSearch(ARequest: THttpRequest; AResponse: THttpResponse);
var
  Q: string;
  Hits: TSearchHitList;
  Ids, Titles, Snips: TStringList;
  I: Integer;
  Hit: TSearchHit;
begin
  Q := ARequest.QueryParam('q');
  Ids := TStringList.Create();
  Titles := TStringList.Create();
  Snips := TStringList.Create();
  if TrimStr(Q) <> '' then
  begin
    Hits := FPorts.Index.Search(Q);
    for I := 0 to Hits.Count - 1 do
    begin
      Hit := Hits[I];
      Ids.Add(Hit.Id);
      Titles.Add(Hit.Title);
      Snips.Add(Hit.SummaryHtml);
    end;
    Hits.Free();
  end;
  AResponse.SetText(200, 'text/html; charset=utf-8',
    RenderSearchPage(Q, Ids, Titles, Snips));
  Ids.Free(); Titles.Free(); Snips.Free();
end;

procedure TLuhmannApp.ServeAllTags(AResponse: THttpResponse);
var
  Tags: TStringList;
  I: Integer;
  Tag, Html: string;
begin
  Tags := FProc.AllTags();
  Html := '<h1>Tags</h1><div class="luh-taglist">';
  for I := 0 to Tags.Count - 1 do
  begin
    Tag := Tags.Get(I);
    Html := Html + '<a class="luh-tag" href="/tags/' + HtmlEscape(Tag) + '">#' +
            HtmlEscape(Tag) + ' (' + IntToStr(FProc.TagCount(Tag)) + ')</a> ';
  end;
  Html := Html + '</div>';
  AResponse.SetText(200, 'text/html; charset=utf-8',
    RenderPage('Tags', Html, nil, nil, nil));
  Tags.Free();
end;

procedure TLuhmannApp.ServeTagList(const ATag: string; AResponse: THttpResponse);
var
  Notes: TStringList;
  I: Integer;
  Id, Html: string;
begin
  Notes := FProc.NotesForTag(ATag);
  Html := '<h1>#' + HtmlEscape(ATag) + '</h1><ul>';
  for I := 0 to Notes.Count - 1 do
  begin
    Id := Notes.Get(I);
    Html := Html + '<li><a href="' + NoteUrl(Id) + '">' +
            HtmlEscape(FProc.TitleOf(Id)) + '</a></li>';
  end;
  Html := Html + '</ul>';
  AResponse.SetText(200, 'text/html; charset=utf-8',
    RenderPage('#' + ATag, Html, nil, nil, nil));
  Notes.Free();
end;

procedure TLuhmannApp.ServeBroken(AResponse: THttpResponse);
var
  Sources, Targets: TStringList;
  I: Integer;
  Html: string;
begin
  Sources := TStringList.Create();
  Targets := TStringList.Create();
  FProc.FindBrokenLinks(Sources, Targets);

  Html := '<h1>Broken links</h1>';
  if Sources.Count = 0 then
    Html := Html + '<p class="luh-none">No broken links. Every cross-reference ' +
            'points to an existing note.</p>'
  else
  begin
    Html := Html + '<p>' + IntToStr(Sources.Count) +
            ' cross-reference(s) point to a note that does not exist. ' +
            'A leading slash (xref:/path) resolves from the root; without it ' +
            'the target is resolved relative to the linking note.</p>';
    Html := Html + '<table class="luh-broken"><tr><th>In note</th>' +
            '<th>Broken target</th></tr>';
    for I := 0 to Sources.Count - 1 do
      Html := Html +
        '<tr><td><a href="' + NoteUrl(Sources.Get(I)) + '">' +
        HtmlEscape(FProc.TitleOf(Sources.Get(I))) + '</a></td>' +
        '<td><code>' + HtmlEscape(Targets.Get(I)) + '</code></td></tr>';
    Html := Html + '</table>';
  end;

  AResponse.SetText(200, 'text/html; charset=utf-8',
    RenderPage('Broken links', Html, nil, nil, nil));
  Sources.Free();
  Targets.Free();
end;

{ Emit a graph node object with id, title, tags array and center flag. }
procedure WriteNode(W: TJSONWriter; AProc: TChangeProcessor; const AId: string;
  ACenter: Boolean);
var
  Tags: TStringList;
  I: Integer;
begin
  W.BeginObject();
  W.WriteString('id', AId);
  W.WriteString('title', AProc.TitleOf(AId));
  W.WriteKey('tags');
  W.BeginArray();
  Tags := AProc.TagsOfNote(AId);
  for I := 0 to Tags.Count - 1 do
    W.WriteStringValue(Tags.Get(I));
  Tags.Free();
  W.EndArray();
  W.WriteKey('center');
  W.WriteBoolValue(ACenter);
  W.EndObject();
end;

procedure TLuhmannApp.ApiGraph(ARequest: THttpRequest; AResponse: THttpResponse);
var
  Note: string;
  W: TJSONWriter;
  OutL, InL, Seen: TStringList;
  I: Integer;
  Nbr: string;
begin
  Note := ARequest.QueryParam('note');
  if Note = '' then
    Note := 'index.adoc';

  W := TJSONWriter.Create();
  W.BeginObject();
  W.WriteString('center', Note);

  OutL := FProc.OutLinkIds(Note);
  InL := FProc.BacklinkIds(Note);

  { nodes: the centre plus all neighbours (deduplicated) }
  Seen := TStringList.Create();
  W.WriteKey('nodes');
  W.BeginArray();
  WriteNode(W, FProc, Note, True);
  Seen.Add(Note);
  for I := 0 to OutL.Count - 1 do
  begin
    Nbr := OutL.Get(I);
    if Seen.IndexOf(Nbr) < 0 then
    begin
      WriteNode(W, FProc, Nbr, False);
      Seen.Add(Nbr);
    end;
  end;
  for I := 0 to InL.Count - 1 do
  begin
    Nbr := InL.Get(I);
    if Seen.IndexOf(Nbr) < 0 then
    begin
      WriteNode(W, FProc, Nbr, False);
      Seen.Add(Nbr);
    end;
  end;
  W.EndArray();

  { edges: centre -> out, in -> centre }
  W.WriteKey('edges');
  W.BeginArray();
  for I := 0 to OutL.Count - 1 do
  begin
    W.BeginObject();
    W.WriteString('from', Note);
    W.WriteString('to', OutL.Get(I));
    W.EndObject();
  end;
  for I := 0 to InL.Count - 1 do
  begin
    W.BeginObject();
    W.WriteString('from', InL.Get(I));
    W.WriteString('to', Note);
    W.EndObject();
  end;
  W.EndArray();

  W.EndObject();
  AResponse.SetText(200, 'application/json', W.ToString());
  W.Free();
  OutL.Free(); InL.Free(); Seen.Free();
end;

procedure TLuhmannApp.ApiGraphAll(AResponse: THttpResponse);
var
  W: TJSONWriter;
  Tags, Notes, OutE: TStringList;
  I, J: Integer;
  Id: string;
begin
  { Build the whole-corpus graph by walking every note's out-links. }
  W := TJSONWriter.Create();
  W.BeginObject();
  W.WriteString('center', '');

  { collect all note ids via the tag index (every note has >=1 tag) }
  Notes := TStringList.Create();
  Tags := FProc.AllTags();
  for I := 0 to Tags.Count - 1 do
  begin
    OutE := FProc.NotesForTag(Tags.Get(I));
    for J := 0 to OutE.Count - 1 do
      if Notes.IndexOf(OutE.Get(J)) < 0 then
        Notes.Add(OutE.Get(J));
    OutE.Free();
  end;
  Tags.Free();

  W.WriteKey('nodes');
  W.BeginArray();
  for I := 0 to Notes.Count - 1 do
    WriteNode(W, FProc, Notes.Get(I), False);
  W.EndArray();

  W.WriteKey('edges');
  W.BeginArray();
  for I := 0 to Notes.Count - 1 do
  begin
    Id := Notes.Get(I);
    OutE := FProc.OutLinkIds(Id);
    for J := 0 to OutE.Count - 1 do
    begin
      { Only emit an edge when its target is also a real node. A dangling
        xref (a link to a note that does not exist) would otherwise produce
        an edge with a nonexistent endpoint, which the graph renderer rejects. }
      if Notes.IndexOf(OutE.Get(J)) >= 0 then
      begin
        W.BeginObject();
        W.WriteString('from', Id);
        W.WriteString('to', OutE.Get(J));
        W.EndObject();
      end;
    end;
    OutE.Free();
  end;
  W.EndArray();

  W.EndObject();
  AResponse.SetText(200, 'application/json', W.ToString());
  W.Free();
  Notes.Free();
end;

procedure TLuhmannApp.ApiBacklinks(ARequest: THttpRequest; AResponse: THttpResponse);
var
  Note: string;
  W: TJSONWriter;
  Ids: TStringList;
  I: Integer;
  Id: string;
begin
  Note := ARequest.QueryParam('note');
  Ids := FProc.BacklinkIds(Note);
  W := TJSONWriter.Create();
  W.BeginArray();
  for I := 0 to Ids.Count - 1 do
  begin
    Id := Ids.Get(I);
    W.BeginObject();
    W.WriteString('note', Id);
    W.WriteString('title', FProc.TitleOf(Id));
    W.EndObject();
  end;
  W.EndArray();
  AResponse.SetText(200, 'application/json', W.ToString());
  W.Free();
  Ids.Free();
end;

procedure TLuhmannApp.ApiTags(AResponse: THttpResponse);
var
  W: TJSONWriter;
  Tags: TStringList;
  I: Integer;
  Tag: string;
begin
  Tags := FProc.AllTags();
  W := TJSONWriter.Create();
  W.BeginArray();
  for I := 0 to Tags.Count - 1 do
  begin
    Tag := Tags.Get(I);
    W.BeginObject();
    W.WriteString('tag', Tag);
    W.WriteInt('count', FProc.TagCount(Tag));
    W.EndObject();
  end;
  W.EndArray();
  AResponse.SetText(200, 'application/json', W.ToString());
  W.Free();
  Tags.Free();
end;

procedure TLuhmannApp.ApiEdit(ARequest: THttpRequest; AResponse: THttpResponse);
var
  Note, AbsPath: string;
begin
  Note := ARequest.QueryParam('note');
  if (Note = '') or ContainsStr(Note, '..') then
  begin
    AResponse.SetText(400, 'text/plain', 'bad note');
    Exit;
  end;
  AbsPath := FPorts.Repo.AbsPathOf(Note);
  if FPorts.Editor.LaunchEditor(AbsPath) then
    AResponse.SetText(200, 'text/plain', 'editor launched: ' + Note)
  else
    AResponse.SetText(400, 'text/plain', 'editor not configured');
end;

procedure TLuhmannApp.Handle(ARequest: THttpRequest; AResponse: THttpResponse);
var
  Path: string;
begin
  Path := ARequest.Path;

  { --- API --- }
  if Path = '/api/graph' then
    ApiGraph(ARequest, AResponse)
  else if Path = '/api/graph/all' then
    ApiGraphAll(AResponse)
  else if Path = '/api/backlinks' then
    ApiBacklinks(ARequest, AResponse)
  else if Path = '/api/tags' then
    ApiTags(AResponse)
  else if Path = '/api/edit' then
    ApiEdit(ARequest, AResponse)

  { --- UI pages --- }
  else if Path = '/search' then
    ServeSearch(ARequest, AResponse)
  else if Path = '/graph' then
    ServeStatic('/graph.html', AResponse)
  else if Path = '/tags' then
    ServeAllTags(AResponse)
  else if StartsStr('/tags/', Path) then
    ServeTagList(Copy(Path, 6, Length(Path) - 6), AResponse)
  else if Path = '/broken' then
    ServeBroken(AResponse)

  { --- static assets (known extensions) --- }
  else if EndsText('.css', Path) or EndsText('.js', Path) or
          EndsText('.svg', Path) or EndsText('.png', Path) or
          EndsText('.jpg', Path) then
    ServeStatic(Path, AResponse)

  { --- note pages (default) --- }
  else
    ServeNotePage(PathToNoteId(Path), AResponse);
end;

end.
