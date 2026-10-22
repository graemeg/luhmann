{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Tests for the filesystem note repository and the asciidoctor renderer
  adapters.  The repository runs against a freshly-built notes directory; the
  real-render test is skipped when asciidoctor is not installed, while the
  failure paths use small shell scripts standing in for asciidoctor. }

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
  protected
    procedure SetUp; override;
  published
    procedure TestRender;
    procedure TestRenderMissingExeIsReported;
    procedure TestRenderFailureShowsEscapedOutput;
    procedure TestRenderManyFailureIsReported;
  end;

  { The startup probe that refuses to run with an unusable asciidoctor. }
  TCheckAsciidoctorTests = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure TestMissingExe;
    procedure TestFailingExe;
    procedure TestWorkingExeReportsVersion;
  end;

implementation

uses
  Generics.Collections, Process, Luhmann.Ports, Luhmann.Adapters, Luhmann.Config;

const
  DIR = '/tmp/luh-test-repo';
  BIN = '/tmp/luh-test-bin';
  MISSING_EXE = '/tmp/luh-test-bin/no-such-asciidoctor';
  FAILING_EXE = '/tmp/luh-test-bin/failing-asciidoctor';
  FAKE_EXE    = '/tmp/luh-test-bin/fake-asciidoctor';

{ Write an executable shell script to APath. }
procedure WriteScript(const APath, ABody: string);
var
  P: TProcess;
begin
  WriteFile(APath, '#!/bin/sh'#10 + ABody + #10);
  P := TProcess.Create(nil);
  P.Executable := '/bin/chmod';
  P.Parameters.Add('755');
  P.Parameters.Add(APath);
  P.Execute();
  P.WaitOnExit();
end;

{ Stand-in asciidoctor executables: one that fails with markup in its output,
  one that answers --version like the real thing. }
procedure MakeFakeExes;
begin
  ForceDirectories(BIN);
  WriteScript(FAILING_EXE, 'echo "<oops> & bang"; exit 3');
  WriteScript(FAKE_EXE, 'echo "Asciidoctor 9.9.9 [https://asciidoctor.org]"');
end;

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

procedure TAsciidoctorRendererTests.SetUp;
begin
  ForceDirectories(DIR + '/.luhmann/tmp');
  MakeFakeExes();
end;

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

{ An asciidoctor that cannot be started must not yield an empty note: the
  body says rendering failed and names the executable. }
procedure TAsciidoctorRendererTests.TestRenderMissingExeIsReported;
var
  html: string;
begin
  html := TAsciidoctorRenderer.Create(MISSING_EXE, DIR + '/.luhmann/tmp', 1)
            .Render('= Apple'#10);
  AssertContains('error block', 'luh-render-error', html);
  AssertContains('names the executable', MISSING_EXE, html);
  AssertContains('exit status', '127', html);
end;

procedure TAsciidoctorRendererTests.TestRenderFailureShowsEscapedOutput;
var
  html: string;
begin
  html := TAsciidoctorRenderer.Create(FAILING_EXE, DIR + '/.luhmann/tmp', 1)
            .Render('= Apple'#10);
  AssertContains('error block', 'luh-render-error', html);
  AssertContains('exit status', '3', html);
  AssertContains('escaped output', '&lt;oops&gt; &amp; bang', html);
end;

procedure TAsciidoctorRendererTests.TestRenderManyFailureIsReported;
var
  Sources, Htmls: TList<string>;
begin
  Sources := TList<string>.Create();
  Sources.Add('= Apple'#10);
  Sources.Add('= Pear'#10);
  Htmls := TList<string>.Create();
  TAsciidoctorRenderer.Create(MISSING_EXE, DIR + '/.luhmann/tmp', 2)
    .RenderMany(Sources, Htmls);
  AssertEquals('one result per source', 2, Htmls.Count);
  AssertContains('first reported', 'luh-render-error', Htmls.Get(0));
  AssertContains('second reported', 'luh-render-error', Htmls.Get(1));
end;

{ ---- TCheckAsciidoctorTests ---- }

procedure TCheckAsciidoctorTests.SetUp;
begin
  MakeFakeExes();
end;

procedure TCheckAsciidoctorTests.TestMissingExe;
var
  Info: string;
begin
  AssertFalse('missing exe refused', CheckAsciidoctor(MISSING_EXE, Info));
  AssertContains('reason', 'not found', Info);
end;

procedure TCheckAsciidoctorTests.TestFailingExe;
var
  Info: string;
begin
  AssertFalse('failing exe refused', CheckAsciidoctor(FAILING_EXE, Info));
  AssertContains('exit status', '3', Info);
  AssertContains('output', '<oops> & bang', Info);
end;

procedure TCheckAsciidoctorTests.TestWorkingExeReportsVersion;
var
  Info: string;
begin
  AssertTrue('working exe accepted', CheckAsciidoctor(FAKE_EXE, Info));
  AssertEquals('version line', 'Asciidoctor 9.9.9 [https://asciidoctor.org]', Info);
end;

initialization
  RegisterTest(TFilesystemNoteRepositoryTests);
  RegisterTest(TAsciidoctorRendererTests);
  RegisterTest(TCheckAsciidoctorTests);

end.
