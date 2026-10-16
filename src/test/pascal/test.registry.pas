{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Central registry of luhmann test units.  Each test unit self-registers in
  its initialization section; this unit pulls them all in. }

unit Test.Registry;

interface

uses
  Luhmann.Adapters.Tests,
  Luhmann.ChangeProc.Tests,
  Luhmann.Chrome.Tests,
  Luhmann.Config.Tests,
  Luhmann.EditGate.Tests,
  Luhmann.Extract.Tests,
  Luhmann.Graph.Tests,
  Luhmann.Search.Tests,
  Luhmann.TagIndex.Tests,
  Luhmann.Watch.Tests;

implementation

end.
