{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for TPollingWatcher against a real, freshly-built notes
  directory: created and deleted notes show up in the next poll. }

unit Luhmann.Watch.Tests;

interface

uses
  blaise.testing, Luhmann.Watch;

type
  TPollingWatcherTests = class(TTestCase)
  private
    W: TPollingWatcher;
  protected
    procedure SetUp; override;
  published
    procedure TestNoChangesAfterPrime;
    procedure TestCreated;
    procedure TestDeleted;
  end;

implementation

uses
  Luhmann.Ports, Luhmann.Adapters;

const
  DIR = '/tmp/luh-test-watch';

procedure TPollingWatcherTests.SetUp;
var
  Ports: TPorts;
begin
  ForceDirectories(DIR);
  WriteFile(DIR + '/a.adoc', '= A');
  WriteFile(DIR + '/b.adoc', '= B');
  DeleteFile(DIR + '/c.adoc');   { left behind by a previous run }
  Ports := TPorts.Create();
  Ports.Repo := TFilesystemNoteRepository.Create(DIR);
  W := TPollingWatcher.Create(Ports);
  W.Prime();
end;

procedure TPollingWatcherTests.TestNoChangesAfterPrime;
begin
  AssertTrue('no changes after prime', W.Poll().IsEmpty());
end;

procedure TPollingWatcherTests.TestCreated;
var
  cs: TChangeSet;
begin
  WriteFile(DIR + '/c.adoc', '= C');
  cs := W.Poll();
  AssertEquals('created count', 1, cs.Created.Count);
  AssertEquals('created is c', 'c.adoc', cs.Created.Get(0));
end;

procedure TPollingWatcherTests.TestDeleted;
var
  cs: TChangeSet;
begin
  DeleteFile(DIR + '/a.adoc');
  cs := W.Poll();
  AssertEquals('deleted count', 1, cs.Deleted.Count);
  AssertEquals('deleted is a', 'a.adoc', cs.Deleted.Get(0));
end;

initialization
  RegisterTest(TPollingWatcherTests);

end.
