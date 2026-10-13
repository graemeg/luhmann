program config_test;
uses Luhmann.Config, Net.Sockets;
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
  { Absent 'bind' must stay loopback: the default may never expose the server. }
  Check('default bind', c.Bind = '127.0.0.1');
  Check('default bind is loopback', c.BindIsLoopback());
  c.LoadOverrides();
  Check('port override', c.Port = 8080);
  Check('editor override', c.Editor = 'nvim-qt');
  Check('catchall override', c.CatchAll = 'inbox');
  { A file with no 'bind' key must not silently change the bind address. }
  Check('bind unchanged by unrelated keys', c.Bind = '127.0.0.1');

  { --- bind = 0.0.0.0 (all interfaces) --- }
  WriteFile('/tmp/luh-watch/.luhmann.ini', 'bind = 0.0.0.0'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  c.LoadOverrides();
  Check('bind any', c.Bind = '0.0.0.0');
  Check('bind any not loopback', not c.BindIsLoopback());

  { --- bind = a specific interface address --- }
  WriteFile('/tmp/luh-watch/.luhmann.ini', 'bind = 192.168.1.50'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  c.LoadOverrides();
  Check('bind specific', c.Bind = '192.168.1.50');
  Check('bind specific not loopback', not c.BindIsLoopback());
  Check('bind specific resolves', c.BindAddr() = IPv4(192, 168, 1, 50));

  { --- explicit loopback is still loopback --- }
  WriteFile('/tmp/luh-watch/.luhmann.ini', 'bind = 127.0.0.1'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  c.LoadOverrides();
  Check('explicit loopback', c.BindIsLoopback());

  { --- an unparseable address must fail closed, not fall through to 0.0.0.0 --- }
  WriteFile('/tmp/luh-watch/.luhmann.ini', 'bind = not-an-ip'#10);
  c := TConfig.Create('/tmp/luh-watch/');
  c.LoadOverrides();
  Check('bad bind rejected', not c.BindIsValid());
  Check('bad bind stays loopback', c.BindIsLoopback());

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
