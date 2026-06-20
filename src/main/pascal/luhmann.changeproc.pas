{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.changeproc - the orchestration heart of the hexagon.  Owns the link
  graph and tag index and drives the render -> index -> graph/tag pipeline.  It
  speaks only to ports (INoteRepository, IAsciiDocRenderer, ISearchIndex,
  IReloadNotifier, ILogger), so it is fully testable against in-memory fakes.

  Rendered HTML for each note is cached in memory (id -> body html) so the web
  layer can serve a page without re-rendering and the chrome layer can append
  backlinks.
}
unit Luhmann.ChangeProc;

interface

uses
  Classes,
  Generics.Collections,
  Luhmann.Model,
  Luhmann.Ports,
  Luhmann.Graph,
  Luhmann.TagIndex;

type
  TChangeProcessor = class
  private
    FPorts:    TPorts;
    FGraph:    TLinkGraph;
    FTags:     TTagIndex;
    FCatchAll: string;
    { id -> rendered full HTML document }
    FHtml:     TOrderedDictionary<string, string>;
    { id -> note title }
    FTitles:   TOrderedDictionary<string, string>;
    procedure IndexOne(const AId: string);
  public
    constructor Create(APorts: TPorts; const ACatchAll: string);
    destructor Destroy; override;

    { Full build: clear everything and (re)process every note. }
    procedure BuildAll;

    { Incremental: a note was created or modified. }
    procedure OnUpsert(const AId: string);

    { Incremental: a note was deleted. }
    procedure OnDelete(const AId: string);

    { --- queries used by the web layer --- }

    { Rendered HTML document for a note, or '' if unknown. }
    function HtmlOf(const AId: string): string;
    function TitleOf(const AId: string): string;
    function BacklinkIds(const AId: string): TStringList;
    function OutLinkIds(const AId: string): TStringList;
    function TagsOfNote(const AId: string): TStringList;
    function AllTags: TStringList;
    function NotesForTag(const ATag: string): TStringList;
    function TagCount(const ATag: string): Integer;
    function HasNote(const AId: string): Boolean;

    property Graph: TLinkGraph read FGraph;
    property Tags: TTagIndex read FTags;
  end;

implementation

uses
  Luhmann.Extract,
  Luhmann.Util;

constructor TChangeProcessor.Create(APorts: TPorts; const ACatchAll: string);
begin
  FPorts := APorts;
  if ACatchAll = '' then
    FCatchAll := DEFAULT_CATCH_ALL
  else
    FCatchAll := ACatchAll;
  FGraph := TLinkGraph.Create();
  FTags  := TTagIndex.Create(FCatchAll);
  FHtml   := TOrderedDictionary<string, string>.Create();
  FTitles := TOrderedDictionary<string, string>.Create();
end;

destructor TChangeProcessor.Destroy;
begin
  FGraph.Free();
  FTags.Free();
  FHtml.Free();
  FTitles.Free();
  inherited Destroy;
end;

procedure TChangeProcessor.IndexOne(const AId: string);
var
  Source, Html, Title, BaseDir: string;
  Tags, Links: TStringList;
  Note: TNote;
  I: Integer;
begin
  Source := FPorts.Repo.ReadSource(AId);

  Title := ExtractTitle(Source);
  if Title = '' then
    Title := AId;
  Html := FPorts.Renderer.Render(Source);
  BaseDir := DirOf(AId);

  Tags  := ExtractTags(Source);
  Links := ExtractOutLinks(Source, BaseDir);

  { Update derived structures. }
  FGraph.SetOutLinks(AId, Links);
  FTags.SetTags(AId, Tags);

  if FHtml.ContainsKey(AId) then
    FHtml.SetItem(AId, Html)
  else
    FHtml.Add(AId, Html);
  if FTitles.ContainsKey(AId) then
    FTitles.SetItem(AId, Title)
  else
    FTitles.Add(AId, Title);

  { Feed the full-text index. }
  Note := TNote.Create(AId);
  Note.Title := Title;
  Note.BodyHtml := Html;
  for I := 0 to Tags.Count - 1 do
    Note.Tags.Add(Tags.Get(I));
  FPorts.Index.Upsert(Note);
  Note.Free();

  Tags.Free();
  Links.Free();
end;

procedure TChangeProcessor.BuildAll;
var
  Ids: TStringList;
  I: Integer;
  Id: string;
begin
  FGraph.Clear();
  FTags.Clear();
  FPorts.Index.Clear();

  Ids := FPorts.Repo.ListNoteIds();
  FPorts.Log.Info('Building ' + IntToStr(Ids.Count) + ' notes');
  for I := 0 to Ids.Count - 1 do
  begin
    Id := Ids.Get(I);
    { Per-note progress so a slow or hanging render is visible. }
    FPorts.Log.Info('  [' + IntToStr(I + 1) + '/' + IntToStr(Ids.Count) +
                    '] ' + Id);
    IndexOne(Id);
  end;
  FPorts.Log.Info('Build complete: ' + IntToStr(Ids.Count) + ' notes');
  Ids.Free();
end;

procedure TChangeProcessor.OnUpsert(const AId: string);
begin
  if FPorts.Log <> nil then
    FPorts.Log.Info('Upsert ' + AId);
  IndexOne(AId);
  if FPorts.Reload <> nil then
    FPorts.Reload.NotifyReload();
end;

procedure TChangeProcessor.OnDelete(const AId: string);
begin
  if FPorts.Log <> nil then
    FPorts.Log.Info('Delete ' + AId);
  FGraph.RemoveNote(AId);
  FTags.RemoveNote(AId);
  FPorts.Index.Remove(AId);
  if FHtml.ContainsKey(AId) then
    FHtml.Remove(AId);
  if FTitles.ContainsKey(AId) then
    FTitles.Remove(AId);
  if FPorts.Reload <> nil then
    FPorts.Reload.NotifyReload();
end;

function TChangeProcessor.HtmlOf(const AId: string): string;
begin
  if not FHtml.TryGetValue(AId, Result) then
    Result := '';
end;

function TChangeProcessor.TitleOf(const AId: string): string;
begin
  if not FTitles.TryGetValue(AId, Result) then
    Result := AId;
end;

function TChangeProcessor.BacklinkIds(const AId: string): TStringList;
begin
  Result := FGraph.BacklinksOf(AId);
end;

function TChangeProcessor.OutLinkIds(const AId: string): TStringList;
begin
  Result := FGraph.OutLinksOf(AId);
end;

function TChangeProcessor.TagsOfNote(const AId: string): TStringList;
begin
  Result := FTags.TagsOf(AId);
end;

function TChangeProcessor.AllTags: TStringList;
begin
  Result := FTags.AllTags();
end;

function TChangeProcessor.NotesForTag(const ATag: string): TStringList;
begin
  Result := FTags.NotesWithTag(ATag);
end;

function TChangeProcessor.TagCount(const ATag: string): Integer;
begin
  Result := FTags.CountForTag(ATag);
end;

function TChangeProcessor.HasNote(const AId: string): Boolean;
begin
  Result := FHtml.ContainsKey(AId);
end;

end.
