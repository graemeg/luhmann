{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Tests for the filesystem note repository and the asciidoctor renderer
  adapters.  The repository runs against a freshly-built notes directory; the
  renderer test is skipped when asciidoctor is not installed. }

unit Luhmann.Adapters.Tests;

interface

uses
  blaise.testing;

type
  TFilesystemNoteRepositoryTests = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestListNoteIds;
    procedure TestListSkipsLuhmannDirAndNonAdoc;
    procedure TestReadSource;
    procedure TestAbsPathOf;
    procedure TestMtimeOf;
    procedure TestExists;
  end;

  TAsciidoctorRendererTests = class(TTestCase)
  published
    procedure TestRender;
  end;

implementation

uses
  Generics.Collections, Luhmann.Ports, Luhmann.Adapters, Luhmann.Config;

const
  DIR = '/tmp/luh-test-repo';

{ ---- TFilesystemNoteRepositoryTests ---- }

procedure TFilesystemNoteRepositoryTests.SetUp;
begin
  ForceDirectories(DIR + '/fruit');
  ForceDirectories(DIR + '/.luhmann/tmp');
  WriteFile(DIR + '/index.adoc', '= Home'#10);
  WriteFile(DIR + '/fruit/apple.adoc', '= Apple'#10);
  WriteFile(DIR + '/notes.txt', 'not a note');
  WriteFile(DIR + '/.luhmann/tmp/scratch.adoc', '= Scratch'#10);
end;

procedure TFilesystemNoteRepositoryTests.TestListNoteIds;
var
  ids: TList<string>;
begin
  ids := TFilesystemNoteRepository.Create(DIR).ListNoteIds();
  AssertEquals('note count', 2, ids.Count);
  AssertTrue('index listed', ids.IndexOf('index.adoc') >= 0);
  AssertTrue('nested note listed', ids.IndexOf('fruit/apple.adoc') >= 0);
end;

procedure TFilesystemNoteRepositoryTests.TestListSkipsLuhmannDirAndNonAdoc;
var
  ids: TList<string>;
begin
  ids := TFilesystemNoteRepository.Create(DIR + '/').ListNoteIds();
  AssertTrue('.luhmann pruned', ids.IndexOf('.luhmann/tmp/scratch.adoc') < 0);
  AssertTrue('non-adoc ignored', ids.IndexOf('notes.txt') < 0);
end;

procedure TFilesystemNoteRepositoryTests.TestReadSource;
begin
  AssertEquals('source', '= Apple'#10,
    TFilesystemNoteRepository.Create(DIR).ReadSource('fruit/apple.adoc'));
end;

procedure TFilesystemNoteRepositoryTests.TestAbsPathOf;
begin
  AssertEquals('abs path', DIR + '/fruit/apple.adoc',
    TFilesystemNoteRepository.Create(DIR + '/').AbsPathOf('fruit/apple.adoc'));
end;

procedure TFilesystemNoteRepositoryTests.TestMtimeOf;
begin
  AssertTrue('mtime > 0',
    TFilesystemNoteRepository.Create(DIR).MtimeOf('index.adoc') > 0);
end;

procedure TFilesystemNoteRepositoryTests.TestExists;
var
  Repo: INoteRepository;
begin
  Repo := TFilesystemNoteRepository.Create(DIR);
  AssertTrue('existing note', Repo.Exists('index.adoc'));
  AssertFalse('missing note', Repo.Exists('nope.adoc'));
end;

{ ---- TAsciidoctorRendererTests ---- }

procedure TAsciidoctorRendererTests.TestRender;
var
  Exe, html: string;
  Rend: IAsciiDocRenderer;
begin
  Exe := TConfig.Create(DIR + '/').ResolveAsciidoctor(GetEnvVar('PATH'));
  if not FileExists(Exe) then
    Ignore('asciidoctor not installed');
  Rend := TAsciidoctorRenderer.Create(Exe, DIR + '/.luhmann/tmp', 1);
  html := Rend.Render('= Apple'#10#10'An *edible* fruit.'#10);
  AssertContains('title rendered', 'Apple', html);
  AssertContains('inline markup rendered', '<strong>edible</strong>', html);
end;

initialization
  RegisterTest(TFilesystemNoteRepositoryTests);
  RegisterTest(TAsciidoctorRendererTests);

end.
