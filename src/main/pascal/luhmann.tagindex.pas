{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.tagindex - the in-memory tag inverted index.  Maintains
  tag -> note-ids and note -> tags.  Notes that resolve to no tags are
  filed under the configured catch-all label so every note is reachable.
}
unit Luhmann.TagIndex;

interface

uses
  Classes,
  Generics.Collections;

type
  TTagIndex = class
  private
    FCatchAll: string;
    FTagToNotes: TOrderedDictionary<string, TList<string>>;
    FNoteToTags: TOrderedDictionary<string, TList<string>>;
    procedure EnsureKey(ADict: TOrderedDictionary<string, TList<string>>;
                        const AKey: string);
    procedure RemoveFromList(AList: TList<string>; const AValue: string);
    procedure DetachNote(const ANoteId: string);
  public
    constructor Create(const ACatchAll: string);
    destructor Destroy; override;

    { Replace the tag set for a note. An empty ATags assigns the catch-all. }
    procedure SetTags(const ANoteId: string; ATags: TStringList);

    { Drop a note from the index entirely. }
    procedure RemoveNote(const ANoteId: string);

    { Distinct tag names, in insertion order. Fresh caller-owned list. }
    function AllTags: TStringList;

    { Note ids carrying a tag. Fresh caller-owned list (empty if unknown). }
    function NotesWithTag(const ATag: string): TStringList;

    { Tags of a note. Fresh caller-owned list. }
    function TagsOf(const ANoteId: string): TStringList;

    { Number of notes carrying a tag (0 if unknown). }
    function CountForTag(const ATag: string): Integer;

    procedure Clear;
  end;

implementation

constructor TTagIndex.Create(const ACatchAll: string);
begin
  if ACatchAll = '' then
    FCatchAll := 'unfiled'
  else
    FCatchAll := ACatchAll;
  FTagToNotes := TOrderedDictionary<string, TList<string>>.Create();
  FNoteToTags := TOrderedDictionary<string, TList<string>>.Create();
end;

destructor TTagIndex.Destroy;
begin
  Clear();
  FTagToNotes.Free();
  FNoteToTags.Free();
  inherited Destroy;
end;

procedure TTagIndex.Clear;
var
  I: Integer;
  Lst: TList<string>;
begin
  { TOrderedDictionary has no Clear; free value lists then rebuild empty. }
  for I := 0 to FTagToNotes.Count - 1 do
  begin
    Lst := FTagToNotes.Values[I];
    Lst.Free();
  end;
  FTagToNotes.Free();
  FTagToNotes := TOrderedDictionary<string, TList<string>>.Create();

  for I := 0 to FNoteToTags.Count - 1 do
  begin
    Lst := FNoteToTags.Values[I];
    Lst.Free();
  end;
  FNoteToTags.Free();
  FNoteToTags := TOrderedDictionary<string, TList<string>>.Create();
end;

procedure TTagIndex.EnsureKey(ADict: TOrderedDictionary<string, TList<string>>;
                              const AKey: string);
begin
  if not ADict.ContainsKey(AKey) then
    ADict.Add(AKey, TList<string>.Create());
end;

procedure TTagIndex.RemoveFromList(AList: TList<string>; const AValue: string);
var
  Idx: Integer;
begin
  if AList = nil then
    Exit;
  Idx := AList.IndexOf(AValue);
  if Idx >= 0 then
    AList.Delete(Idx);
end;

procedure TTagIndex.DetachNote(const ANoteId: string);
var
  OldTags, Notes: TList<string>;
  I: Integer;
  Tag: string;
begin
  if not FNoteToTags.TryGetValue(ANoteId, OldTags) then
    Exit;
  for I := 0 to OldTags.Count - 1 do
  begin
    Tag := OldTags[I];
    if FTagToNotes.TryGetValue(Tag, Notes) then
      RemoveFromList(Notes, ANoteId);
  end;
  OldTags.Clear();
end;

procedure TTagIndex.SetTags(const ANoteId: string; ATags: TStringList);
var
  NoteTags, Notes: TList<string>;
  I: Integer;
  Tag: string;
  HasAny: Boolean;
begin
  EnsureKey(FNoteToTags, ANoteId);
  DetachNote(ANoteId);
  FNoteToTags.TryGetValue(ANoteId, NoteTags);

  HasAny := False;
  if ATags <> nil then
    for I := 0 to ATags.Count - 1 do
    begin
      Tag := ATags.Get(I);
      if Tag = '' then
        Continue;
      HasAny := True;
      if NoteTags.IndexOf(Tag) < 0 then
        NoteTags.Add(Tag);
      EnsureKey(FTagToNotes, Tag);
      FTagToNotes.TryGetValue(Tag, Notes);
      if Notes.IndexOf(ANoteId) < 0 then
        Notes.Add(ANoteId);
    end;

  if not HasAny then
  begin
    { Catch-all assignment for untagged notes. }
    NoteTags.Add(FCatchAll);
    EnsureKey(FTagToNotes, FCatchAll);
    FTagToNotes.TryGetValue(FCatchAll, Notes);
    if Notes.IndexOf(ANoteId) < 0 then
      Notes.Add(ANoteId);
  end;
end;

procedure TTagIndex.RemoveNote(const ANoteId: string);
var
  NoteTags: TList<string>;
begin
  DetachNote(ANoteId);
  if FNoteToTags.TryGetValue(ANoteId, NoteTags) then
  begin
    NoteTags.Free();
    FNoteToTags.Remove(ANoteId);
  end;
end;

function TTagIndex.AllTags: TStringList;
var
  I: Integer;
begin
  Result := TStringList.Create();
  for I := 0 to FTagToNotes.Count - 1 do
    Result.Add(FTagToNotes.Keys[I]);
end;

function TTagIndex.NotesWithTag(const ATag: string): TStringList;
var
  Notes: TList<string>;
  I: Integer;
begin
  Result := TStringList.Create();
  if FTagToNotes.TryGetValue(ATag, Notes) then
    for I := 0 to Notes.Count - 1 do
      Result.Add(Notes[I]);
end;

function TTagIndex.TagsOf(const ANoteId: string): TStringList;
var
  Tags: TList<string>;
  I: Integer;
begin
  Result := TStringList.Create();
  if FNoteToTags.TryGetValue(ANoteId, Tags) then
    for I := 0 to Tags.Count - 1 do
      Result.Add(Tags[I]);
end;

function TTagIndex.CountForTag(const ATag: string): Integer;
var
  Notes: TList<string>;
begin
  if FTagToNotes.TryGetValue(ATag, Notes) then
    Result := Notes.Count
  else
    Result := 0;
end;

end.
