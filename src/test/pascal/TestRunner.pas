{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Test runner for luhmann.

  Pulls in every test unit via Test.Registry (each self-registers through its
  initialization section), then runs them with the text runner.  Exits 0 when
  everything passes, 1 otherwise. }

program TestRunner;

uses
  blaise.testing,
  blaise.testing.runner.text,
  Test.Registry;

begin
  Halt(RunAll());
end.
