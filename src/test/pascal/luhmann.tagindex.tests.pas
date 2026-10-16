{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for TTagIndex: tag-to-note mapping, the 'unfiled' default tag,
  re-tagging and note removal. }

unit Luhmann.TagIndex.Tests;

interface

uses
  blaise.testing, Luhmann.TagIndex;

type
  TTagIndexTests = class(TTestCase)
  private
    T: TTagIndex;
  protected
    procedure SetUp; override;
  published
    procedure TestNotesWithTag;
    procedure TestUntaggedNoteIsUnfiled;
    procedure TestCountForTag;
    procedure TestTagsOf;
    procedure TestRetag;
    procedure TestRemoveNote;
  end;

implementation

uses
  Generics.Collections, Luhmann.Test.Support;

procedure TTagIndexTests.SetUp;
begin
  T := TTagIndex.Create('unfiled');
  T.SetTags('fruit/apple.adoc', L('fruit', 'pome'));
  T.SetTags('fruit/orange.adoc', L('fruit', 'citrus'));
  T.SetTags('index.adoc', L('', ''));
end;

procedure TTagIndexTests.TestNotesWithTag;
begin
  AssertEquals('notes tagged fruit', 2, T.NotesWithTag('fruit').Count);
end;

procedure TTagIndexTests.TestUntaggedNoteIsUnfiled;
var
  notes: TList<string>;
begin
  notes := T.NotesWithTag('unfiled');
  AssertEquals('unfiled count', 1, notes.Count);
  AssertEquals('index is unfiled', 'index.adoc', notes.Get(0));
end;

procedure TTagIndexTests.TestCountForTag;
begin
  AssertEquals('CountForTag citrus', 1, T.CountForTag('citrus'));
end;

procedure TTagIndexTests.TestTagsOf;
begin
  AssertEquals('apple tags', 2, T.TagsOf('fruit/apple.adoc').Count);
end;

procedure TTagIndexTests.TestRetag;
begin
  T.SetTags('fruit/apple.adoc', L('fruit', 'edible'));
  AssertEquals('pome now empty', 0, T.CountForTag('pome'));
  AssertEquals('edible has apple', 1, T.CountForTag('edible'));
end;

procedure TTagIndexTests.TestRemoveNote;
begin
  T.RemoveNote('index.adoc');
  AssertEquals('unfiled empty after index removed', 0, T.CountForTag('unfiled'));
end;

initialization
  RegisterTest(TTagIndexTests);

end.
