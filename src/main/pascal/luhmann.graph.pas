{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.graph - the in-memory directed link graph.  Nodes are NoteIds;
  edges are reference relationships.  Both the forward (out) and inverse (in,
  i.e. backlink) adjacency are maintained incrementally.

  Edges are stored as id STRINGS in both directions, never as TNote object
  references, so the graph is free of ARC reference cycles by construction.
}
unit Luhmann.Graph;

interface

uses
  Classes,
  Generics.Collections;

type
  TLinkGraph = class
  private
    { id -> list of ids it links to }
    FOut: TOrderedDictionary<string, TList<string>>;
    { id -> list of ids that link to it (backlinks) }
    FIn:  TOrderedDictionary<string, TList<string>>;
    procedure EnsureKey(ADict: TOrderedDictionary<string, TList<string>>;
                        const AKey: string);
    procedure RemoveFromList(AList: TList<string>; const AValue: string);
    procedure ClearOutEdgesOf(const AFrom: string);
  public
    constructor Create;
    destructor Destroy; override;

    { Replace the complete set of out-edges for AFrom with ATargets, updating
      the inverse (backlink) adjacency accordingly. Adding a note with no
      out-links still registers the node. }
    procedure SetOutLinks(const AFrom: string; ATargets: TStringList);

    { Remove a note entirely: drops its out-edges and their inverse entries.
      Inbound edges pointing at AFrom are left in place (they become dangling)
      so the referencing notes still show a broken link. }
    procedure RemoveNote(const AFrom: string);

    { Backlinks: ids of notes that reference AId. Returns a fresh list owned by
      the caller (empty if none). }
    function BacklinksOf(const AId: string): TStringList;

    { Forward links: ids AId references. Fresh caller-owned list. }
    function OutLinksOf(const AId: string): TStringList;

    procedure Clear;
  end;

implementation

constructor TLinkGraph.Create;
begin
  FOut := TOrderedDictionary<string, TList<string>>.Create();
  FIn  := TOrderedDictionary<string, TList<string>>.Create();
end;

destructor TLinkGraph.Destroy;
begin
  Clear();
  FOut.Free();
  FIn.Free();
  inherited Destroy;
end;

procedure TLinkGraph.Clear;
var
  I: Integer;
  Lst: TList<string>;
begin
  { TOrderedDictionary has no Clear; free the value lists then rebuild the
    dictionaries empty. }
  for I := 0 to FOut.Count - 1 do
  begin
    Lst := FOut.Values[I];
    Lst.Free();
  end;
  FOut.Free();
  FOut := TOrderedDictionary<string, TList<string>>.Create();

  for I := 0 to FIn.Count - 1 do
  begin
    Lst := FIn.Values[I];
    Lst.Free();
  end;
  FIn.Free();
  FIn := TOrderedDictionary<string, TList<string>>.Create();
end;

procedure TLinkGraph.EnsureKey(ADict: TOrderedDictionary<string, TList<string>>;
                               const AKey: string);
var
  Tmp: TList<string>;
begin
  if not ADict.ContainsKey(AKey) then
    ADict.Add(AKey, TList<string>.Create());
end;

procedure TLinkGraph.RemoveFromList(AList: TList<string>; const AValue: string);
var
  Idx: Integer;
begin
  if AList = nil then
    Exit;
  Idx := AList.IndexOf(AValue);
  if Idx >= 0 then
    AList.Delete(Idx);
end;

procedure TLinkGraph.ClearOutEdgesOf(const AFrom: string);
var
  Old, InList: TList<string>;
  I: Integer;
  Target: string;
begin
  if not FOut.TryGetValue(AFrom, Old) then
    Exit;
  { For each old target, drop AFrom from that target's inbound list. }
  for I := 0 to Old.Count - 1 do
  begin
    Target := Old[I];
    if FIn.TryGetValue(Target, InList) then
      RemoveFromList(InList, AFrom);
  end;
  Old.Clear();
end;

procedure TLinkGraph.SetOutLinks(const AFrom: string; ATargets: TStringList);
var
  OutList, InList: TList<string>;
  I: Integer;
  Target: string;
begin
  EnsureKey(FOut, AFrom);
  ClearOutEdgesOf(AFrom);
  FOut.TryGetValue(AFrom, OutList);

  if ATargets <> nil then
    for I := 0 to ATargets.Count - 1 do
    begin
      Target := ATargets.Get(I);
      OutList.Add(Target);
      EnsureKey(FIn, Target);
      FIn.TryGetValue(Target, InList);
      if InList.IndexOf(AFrom) < 0 then
        InList.Add(AFrom);
    end;
end;

procedure TLinkGraph.RemoveNote(const AFrom: string);
var
  OutList: TList<string>;
begin
  ClearOutEdgesOf(AFrom);
  if FOut.TryGetValue(AFrom, OutList) then
  begin
    OutList.Free();
    FOut.Remove(AFrom);
  end;
  { FIn[AFrom] is deliberately left: inbound edges become dangling. }
end;

function TLinkGraph.BacklinksOf(const AId: string): TStringList;
var
  Src: TList<string>;
  I: Integer;
begin
  Result := TStringList.Create();
  if FIn.TryGetValue(AId, Src) then
    for I := 0 to Src.Count - 1 do
      Result.Add(Src[I]);
end;

function TLinkGraph.OutLinksOf(const AId: string): TStringList;
var
  Src: TList<string>;
  I: Integer;
begin
  Result := TStringList.Create();
  if FOut.TryGetValue(AId, Src) then
    for I := 0 to Src.Count - 1 do
      Result.Add(Src[I]);
end;

end.
