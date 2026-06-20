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
    procedure IndexWith(const AId, ASource, AHtml: string);
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

    { Every real note id, in insertion order. Fresh caller-owned list. }
    function AllNoteIds: TStringList;

    { Find broken cross-references: out-links whose target is not a real note.
      Fills ASources[i] (the note containing the link) and ATargets[i] (the
      missing target id) in parallel. Both lists are cleared first. }
    procedure FindBrokenLinks(ASources, ATargets: TStringList);

    property Graph: TLinkGraph read FGraph;
    property Tags: TTagIndex read FTags;
  end;

implementation

uses
  Luhmann.Extract,
  Luhmann.Util;

{ Monotonic-ish wall clock in nanoseconds (RTL builtin). }
function _TimeNow(): Int64; external name '_TimeNow';

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

{ Update all derived structures for a note given its already-known source and
  rendered HTML. The render (the slow step) is done by the caller, so this is
  pure in-memory work and is shared by the serial and parallel build paths. }
procedure TChangeProcessor.IndexWith(const AId, ASource, AHtml: string);
var
  Title, BaseDir: string;
  Tags, Links: TStringList;
  Note: TNote;
  I: Integer;
begin
  Title := ExtractTitle(ASource);
  if Title = '' then
    Title := AId;
  BaseDir := DirOf(AId);

  Tags  := ExtractTags(ASource);
  Links := ExtractOutLinks(ASource, BaseDir);

  FGraph.SetOutLinks(AId, Links);
  FTags.SetTags(AId, Tags);

  if FHtml.ContainsKey(AId) then
    FHtml.SetItem(AId, AHtml)
  else
    FHtml.Add(AId, AHtml);
  if FTitles.ContainsKey(AId) then
    FTitles.SetItem(AId, Title)
  else
    FTitles.Add(AId, Title);

  Note := TNote.Create(AId);
  Note.Title := Title;
  Note.BodyHtml := AHtml;
  for I := 0 to Tags.Count - 1 do
    Note.Tags.Add(Tags.Get(I));
  FPorts.Index.Upsert(Note);
  Note.Free();

  Tags.Free();
  Links.Free();
end;

{ Incremental single-note index: read + render this one note, then index it. }
procedure TChangeProcessor.IndexOne(const AId: string);
var
  Source, Html: string;
begin
  Source := FPorts.Repo.ReadSource(AId);
  Html := FPorts.Renderer.Render(Source);
  IndexWith(AId, Source, Html);
end;

procedure TChangeProcessor.BuildAll;
var
  Ids, Sources, Htmls: TStringList;
  I: Integer;
  Id: string;
  TStart, TEnd, ElapsedMs: Int64;
begin
  FGraph.Clear();
  FTags.Clear();
  FPorts.Index.Clear();

  Ids := FPorts.Repo.ListNoteIds();
  FPorts.Log.Info('Building ' + IntToStr(Ids.Count) + ' notes');

  { Read every source up front, then render them all (potentially in parallel)
    in one batch, then do the fast in-memory indexing serially. Timing brackets
    the render+index work. }
  TStart := _TimeNow();

  Sources := TStringList.Create();
  for I := 0 to Ids.Count - 1 do
    Sources.Add(FPorts.Repo.ReadSource(Ids.Get(I)));

  Htmls := TStringList.Create();
  FPorts.Renderer.RenderMany(Sources, Htmls);

  for I := 0 to Ids.Count - 1 do
  begin
    Id := Ids.Get(I);
    IndexWith(Id, Sources.Get(I), Htmls.Get(I));
  end;

  TEnd := _TimeNow();
  ElapsedMs := (TEnd - TStart) div 1000000;

  FPorts.Log.Info('Build complete: ' + IntToStr(Ids.Count) + ' notes in ' +
                  IntToStr(ElapsedMs) + ' ms');

  Sources.Free();
  Htmls.Free();
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

function TChangeProcessor.AllNoteIds: TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create();
  for I := 0 to FHtml.Count - 1 do
    Result.Add(FHtml.Keys[I]);
end;

procedure TChangeProcessor.FindBrokenLinks(ASources, ATargets: TStringList);
var
  Ids, OutL: TStringList;
  I, J: Integer;
  Id, Target: string;
begin
  ASources.Clear();
  ATargets.Clear();
  Ids := AllNoteIds();
  for I := 0 to Ids.Count - 1 do
  begin
    Id := Ids.Get(I);
    OutL := OutLinkIds(Id);
    for J := 0 to OutL.Count - 1 do
    begin
      Target := OutL.Get(J);
      if not HasNote(Target) then
      begin
        ASources.Add(Id);
        ATargets.Add(Target);
      end;
    end;
    OutL.Free();
  end;
  Ids.Free();
end;

end.
