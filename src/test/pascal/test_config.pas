program config_test;
uses Luhmann.Config;
var Pass, Fail: Integer; c: TConfig;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
begin
  Pass:=0; Fail:=0;
  { Self-contained fixture. }
  ForceDirectories('/tmp/luh-watch');
  WriteFile('/tmp/luh-watch/.luhmann.ini',
    'port = 8080'#10'editor = nvim-qt'#10'catch-all-label = inbox'#10'# a comment'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  Check('default port', c.Port = 2022);
  Check('trailing slash stripped', c.RootDir = '/tmp/luh-watch');
  Check('default catchall', c.CatchAll = 'unfiled');
  Check('luhmann dir', c.LuhmannDir = '/tmp/luh-watch/.luhmann');
  Check('site dir', c.SiteDir() = '/tmp/luh-watch/.luhmann/site');
  c.LoadOverrides();
  Check('port override', c.Port = 8080);
  Check('editor override', c.Editor = 'nvim-qt');
  Check('catchall override', c.CatchAll = 'inbox');

  { --- asciidoctor: unset by default, resolved from PATH --- }
  ForceDirectories('/tmp/luh-path-a');
  ForceDirectories('/tmp/luh-path-b');
  ForceDirectories('/tmp/luh-path-empty');
  WriteFile('/tmp/luh-path-a/asciidoctor', '#!/bin/sh'#10);
  WriteFile('/tmp/luh-path-b/asciidoctor', '#!/bin/sh'#10);
  WriteFile('/tmp/luh-watch/.luhmann.ini', 'port = 2022'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  c.LoadOverrides();
  Check('asciidoctor unset by default', c.Asciidoctor = '');
  Check('asciidoctor found on PATH',
    c.ResolveAsciidoctor('/tmp/luh-path-empty:/tmp/luh-path-b') =
      '/tmp/luh-path-b/asciidoctor');
  Check('asciidoctor first PATH match wins',
    c.ResolveAsciidoctor('/tmp/luh-path-a:/tmp/luh-path-b') =
      '/tmp/luh-path-a/asciidoctor');
  Check('asciidoctor empty PATH entries skipped',
    c.ResolveAsciidoctor('::/tmp/luh-path-b:') = '/tmp/luh-path-b/asciidoctor');
  Check('asciidoctor trailing slash in PATH entry',
    c.ResolveAsciidoctor('/tmp/luh-path-b/') = '/tmp/luh-path-b/asciidoctor');
  Check('asciidoctor not on PATH falls back',
    c.ResolveAsciidoctor('/tmp/luh-path-empty') = '/usr/bin/asciidoctor');
  Check('asciidoctor empty PATH falls back',
    c.ResolveAsciidoctor('') = '/usr/bin/asciidoctor');

  { An explicit setting wins over PATH, even when PATH has a match. }
  WriteFile('/tmp/luh-watch/.luhmann.ini',
    'asciidoctor = /opt/custom/asciidoctor'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  c.LoadOverrides();
  Check('asciidoctor explicit setting wins',
    c.ResolveAsciidoctor('/tmp/luh-path-a') = '/opt/custom/asciidoctor');
  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
