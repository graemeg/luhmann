{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for TConfig: defaults, .luhmann.ini overrides, the bind
  address policy and asciidoctor resolution from PATH. }

unit Luhmann.Config.Tests;

interface

uses
  blaise.testing, Luhmann.Config;

type
  TConfigTests = class(TTestCase)
  private
    function LoadIni(const AIni: string): TConfig;
  protected
    procedure SetUp; override;
  published
    procedure TestDefaults;
    procedure TestOverrides;
    procedure TestBindUnchangedByUnrelatedKeys;
    procedure TestBindAnyInterface;
    procedure TestBindSpecificAddress;
    procedure TestBindExplicitLoopback;
    procedure TestBindInvalidFailsClosed;
    procedure TestAsciidoctorUnsetByDefault;
    procedure TestAsciidoctorFoundOnPath;
    procedure TestAsciidoctorFirstPathMatchWins;
    procedure TestAsciidoctorEmptyPathEntriesSkipped;
    procedure TestAsciidoctorTrailingSlashInPathEntry;
    procedure TestAsciidoctorFallback;
    procedure TestAsciidoctorExplicitSettingWins;
  end;

implementation

uses
  Net.Sockets;

const
  DIR = '/tmp/luh-test-config';
  PATH_A = '/tmp/luh-test-path-a';
  PATH_B = '/tmp/luh-test-path-b';
  PATH_EMPTY = '/tmp/luh-test-path-empty';

procedure TConfigTests.SetUp;
begin
  ForceDirectories(DIR);
  ForceDirectories(PATH_A);
  ForceDirectories(PATH_B);
  ForceDirectories(PATH_EMPTY);
  WriteFile(PATH_A + '/asciidoctor', '#!/bin/sh'#10);
  WriteFile(PATH_B + '/asciidoctor', '#!/bin/sh'#10);
end;

{ Write AIni as the fixture's .luhmann.ini and return a config with it loaded. }
function TConfigTests.LoadIni(const AIni: string): TConfig;
begin
  WriteFile(DIR + '/.luhmann.ini', AIni);
  Result := TConfig.Create(DIR + '/');
  Result.LoadOverrides();
end;

procedure TConfigTests.TestDefaults;
var
  c: TConfig;
begin
  WriteFile(DIR + '/.luhmann.ini',
    'port = 8080'#10'editor = nvim-qt'#10'catch-all-label = inbox'#10'# a comment'#10);
  c := TConfig.Create(DIR + '/');
  AssertEquals('default port', 2022, c.Port);
  AssertEquals('trailing slash stripped', DIR, c.RootDir);
  AssertEquals('default catchall', 'unfiled', c.CatchAll);
  AssertEquals('luhmann dir', DIR + '/.luhmann', c.LuhmannDir);
  AssertEquals('site dir', DIR + '/.luhmann/site', c.SiteDir());
  { Absent 'bind' must stay loopback: the default may never expose the server. }
  AssertEquals('default bind', '127.0.0.1', c.Bind);
  AssertTrue('default bind is loopback', c.BindIsLoopback());
end;

procedure TConfigTests.TestOverrides;
var
  c: TConfig;
begin
  c := LoadIni('port = 8080'#10'editor = nvim-qt'#10'catch-all-label = inbox'#10'# a comment'#10);
  AssertEquals('port override', 8080, c.Port);
  AssertEquals('editor override', 'nvim-qt', c.Editor);
  AssertEquals('catchall override', 'inbox', c.CatchAll);
end;

{ A file with no 'bind' key must not silently change the bind address. }
procedure TConfigTests.TestBindUnchangedByUnrelatedKeys;
begin
  AssertEquals('bind unchanged', '127.0.0.1',
    LoadIni('port = 8080'#10'editor = nvim-qt'#10).Bind);
end;

procedure TConfigTests.TestBindAnyInterface;
var
  c: TConfig;
begin
  c := LoadIni('bind = 0.0.0.0'#10);
  AssertEquals('bind any', '0.0.0.0', c.Bind);
  AssertFalse('bind any not loopback', c.BindIsLoopback());
end;

procedure TConfigTests.TestBindSpecificAddress;
var
  c: TConfig;
begin
  c := LoadIni('bind = 192.168.1.50'#10);
  AssertEquals('bind specific', '192.168.1.50', c.Bind);
  AssertFalse('bind specific not loopback', c.BindIsLoopback());
  AssertTrue('bind specific resolves', c.BindAddr() = IPv4(192, 168, 1, 50));
end;

procedure TConfigTests.TestBindExplicitLoopback;
begin
  AssertTrue('explicit loopback', LoadIni('bind = 127.0.0.1'#10).BindIsLoopback());
end;

{ An unparseable address must fail closed, not fall through to 0.0.0.0. }
procedure TConfigTests.TestBindInvalidFailsClosed;
var
  c: TConfig;
begin
  c := LoadIni('bind = not-an-ip'#10);
  AssertFalse('bad bind rejected', c.BindIsValid());
  AssertTrue('bad bind stays loopback', c.BindIsLoopback());
end;

procedure TConfigTests.TestAsciidoctorUnsetByDefault;
begin
  AssertEquals('asciidoctor unset', '', LoadIni('port = 2022'#10).Asciidoctor);
end;

procedure TConfigTests.TestAsciidoctorFoundOnPath;
begin
  AssertEquals('found on PATH', PATH_B + '/asciidoctor',
    LoadIni('port = 2022'#10).ResolveAsciidoctor(PATH_EMPTY + ':' + PATH_B));
end;

procedure TConfigTests.TestAsciidoctorFirstPathMatchWins;
begin
  AssertEquals('first match wins', PATH_A + '/asciidoctor',
    LoadIni('port = 2022'#10).ResolveAsciidoctor(PATH_A + ':' + PATH_B));
end;

procedure TConfigTests.TestAsciidoctorEmptyPathEntriesSkipped;
begin
  AssertEquals('empty entries skipped', PATH_B + '/asciidoctor',
    LoadIni('port = 2022'#10).ResolveAsciidoctor('::' + PATH_B + ':'));
end;

procedure TConfigTests.TestAsciidoctorTrailingSlashInPathEntry;
begin
  AssertEquals('trailing slash', PATH_B + '/asciidoctor',
    LoadIni('port = 2022'#10).ResolveAsciidoctor(PATH_B + '/'));
end;

procedure TConfigTests.TestAsciidoctorFallback;
var
  c: TConfig;
begin
  c := LoadIni('port = 2022'#10);
  AssertEquals('not on PATH', '/usr/bin/asciidoctor', c.ResolveAsciidoctor(PATH_EMPTY));
  AssertEquals('empty PATH', '/usr/bin/asciidoctor', c.ResolveAsciidoctor(''));
end;

{ An explicit setting wins over PATH, even when PATH has a match. }
procedure TConfigTests.TestAsciidoctorExplicitSettingWins;
begin
  AssertEquals('explicit setting wins', '/opt/custom/asciidoctor',
    LoadIni('asciidoctor = /opt/custom/asciidoctor'#10).ResolveAsciidoctor(PATH_A));
end;

initialization
  RegisterTest(TConfigTests);

end.
