{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.model - the domain model at the centre of the hexagon.  Pure data:
  no I/O, no framework, no libc.  A NoteId is just a canonical relative path
  string (e.g. 'fruit/apple.adoc').  Edges are stored as id strings, never as
  object references, so the graph never forms an ARC reference cycle.
}
unit Luhmann.Model;

interface

uses
  Generics.Collections;

const
  { Notes with no tags are filed under this label so every note is reachable
    from the tag index.  Overridable via config in the catch-all label. }
  DEFAULT_CATCH_ALL = 'unfiled';

type
  { A single note. Identified by its canonical relative source path. The body
    HTML is the rendered output; tags and out-links are derived from source. }
  TNote = class
  public
    Id:        string;        { e.g. 'fruit/apple.adoc' }
    Title:     string;
    BodyHtml:  string;        { rendered <body> inner HTML, no chrome }
    Tags:      TList<string>;
    OutLinks:  TList<string>; { NoteIds this note references (xref targets) }
    LastMtime: Int64;
    constructor Create(const AId: string);
  end;

  { A scored search hit. }
  TSearchHit = class
  public
    Id:          string;
    Title:       string;
    Score:       Double;
    SummaryHtml: string;
    constructor Create;
  end;

  { An owning, non-generic list of search hits. Concrete (not a generic
    instantiation) so it can be returned across interface/function boundaries,
    while internally using a generic list (generic fields are permitted). }
  TSearchHitList = class
  private
    FItems: TList<TSearchHit>;
    function GetItem(AIndex: Integer): TSearchHit;
    function GetCount: Integer;
  public
    constructor Create;
    procedure Add(AHit: TSearchHit);
    property Items[AIndex: Integer]: TSearchHit read GetItem; default;
    property Count: Integer read GetCount;
  end;

{ Map a source path to a rendered output path: foo/bar.adoc -> foo/bar.html.
  Non-adoc paths are returned unchanged. }
function SourceToHtml(const APath: string): string;

{ True if APath ends with '.adoc' (case-insensitive on the extension). }
function IsAdoc(const APath: string): Boolean;

implementation

uses
  StrUtils;

constructor TNote.Create(const AId: string);
begin
  Id := AId;
  Title := '';
  BodyHtml := '';
  Tags := TList<string>.Create();
  OutLinks := TList<string>.Create();
  LastMtime := 0;
end;

constructor TSearchHit.Create;
begin
  Id := '';
  Title := '';
  Score := 0.0;
  SummaryHtml := '';
end;

constructor TSearchHitList.Create;
begin
  FItems := TList<TSearchHit>.Create();
end;

procedure TSearchHitList.Add(AHit: TSearchHit);
begin
  FItems.Add(AHit);
end;

function TSearchHitList.GetItem(AIndex: Integer): TSearchHit;
begin
  Result := FItems[AIndex];
end;

function TSearchHitList.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function IsAdoc(const APath: string): Boolean;
begin
  Result := EndsText('.adoc', APath);
end;

function SourceToHtml(const APath: string): string;
begin
  if IsAdoc(APath) then
    { strip '.adoc' (5 chars) and append '.html' }
    Result := Copy(APath, 0, Length(APath) - 5) + '.html'
  else
    Result := APath;
end;

end.
