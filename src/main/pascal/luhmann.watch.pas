{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.watch - a polling directory watcher.  The runtime exposes no inotify
  binding, so changes are detected by periodically re-listing the notes and
  comparing modification times against a remembered snapshot.  Each poll
  reports the created, modified, and deleted note ids since the previous poll.

  This is the ChangeSource adapter.  A driver (a background thread in the
  composition root) calls Poll on an interval and forwards the results to the
  ChangeProcessor; the watcher itself owns no thread, keeping it trivially
  testable.
}
unit Luhmann.Watch;

interface

uses
  Generics.Collections,
  Luhmann.Ports;

type
  { Result of a single poll: three disjoint id lists. The watcher owns nothing
    here; the caller frees the returned object (which frees its lists). }
  TChangeSet = class
  public
    Created:  TList<string>;
    Modified: TList<string>;
    Deleted:  TList<string>;
    constructor Create;
    function IsEmpty: Boolean;
  end;

  TPollingWatcher = class
  private
    { Holds the repository indirectly: an interface stored as this class's own
      field and called via Self miscompiles on the native backend, so the port
      is reached through the TPorts registry instead. }
    FPorts: TPorts;
    { id -> last seen mtime }
    FSeen: TOrderedDictionary<string, Int64>;
  public
    constructor Create(APorts: TPorts);
    { Establish the initial snapshot without reporting anything (call once
      after the initial build so the first real poll only sees true changes). }
    procedure Prime;
    { Detect changes since the previous poll/prime. Caller owns the result. }
    function Poll: TChangeSet;
  end;

implementation

constructor TChangeSet.Create;
begin
  Created  := TList<string>.Create();
  Modified := TList<string>.Create();
  Deleted  := TList<string>.Create();
end;

function TChangeSet.IsEmpty: Boolean;
begin
  Result := (Created.Count = 0) and (Modified.Count = 0) and (Deleted.Count = 0);
end;

constructor TPollingWatcher.Create(APorts: TPorts);
begin
  FPorts := APorts;
  FSeen := TOrderedDictionary<string, Int64>.Create();
end;

procedure TPollingWatcher.Prime;
var
  Ids: TList<string>;
  I: Integer;
  Id: string;
begin
  Ids := FPorts.Repo.ListNoteIds();
  for I := 0 to Ids.Count - 1 do
  begin
    Id := Ids.Get(I);
    if not FSeen.ContainsKey(Id) then
      FSeen.Add(Id, FPorts.Repo.MtimeOf(Id))
    else
      FSeen.SetItem(Id, FPorts.Repo.MtimeOf(Id));
  end;
end;

function TPollingWatcher.Poll: TChangeSet;
var
  Ids, Current: TList<string>;
  I: Integer;
  Id: string;
  Mt, OldMt: Int64;
begin
  Result := TChangeSet.Create();
  Ids := FPorts.Repo.ListNoteIds();

  { Detect creates and modifications. Track which ids exist now. }
  Current := TList<string>.Create();
  for I := 0 to Ids.Count - 1 do
  begin
    Id := Ids.Get(I);
    Current.Add(Id);
    Mt := FPorts.Repo.MtimeOf(Id);
    if not FSeen.TryGetValue(Id, OldMt) then
    begin
      Result.Created.Add(Id);
      FSeen.Add(Id, Mt);
    end
    else if Mt <> OldMt then
    begin
      Result.Modified.Add(Id);
      FSeen.SetItem(Id, Mt);
    end;
  end;

  { Detect deletions: ids previously seen but no longer present. Collect first
    (cannot remove while iterating the dictionary). }
  for I := 0 to FSeen.Count - 1 do
  begin
    Id := FSeen.Keys[I];
    if Current.IndexOf(Id) < 0 then
      Result.Deleted.Add(Id);
  end;
  for I := 0 to Result.Deleted.Count - 1 do
    FSeen.Remove(Result.Deleted.Get(I));
end;

end.
