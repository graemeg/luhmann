{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.ports - the hexagon's port interfaces (driven / outbound side).
  The domain core depends only on these; concrete adapters in the
  luhmann.adapter.* units implement them.  Interfaces are ARC-managed, so no
  manual freeing of port references is needed.
}
unit Luhmann.Ports;

interface

uses
  Generics.Collections,
  Luhmann.Model;

type
  { Reads note sources from the underlying store (the filesystem) and maps
    between source paths and canonical NoteIds. }
  INoteRepository = interface
    { Canonical relative ids of every .adoc note under the root. Caller owns. }
    function ListNoteIds: TList<string>;
    { Raw AsciiDoc source for a note id, or '' if missing. }
    function ReadSource(const AId: string): string;
    { Absolute filesystem path of a note's source. }
    function AbsPathOf(const AId: string): string;
    { Modification time of a note's source, or -1 if missing. }
    function MtimeOf(const AId: string): Int64;
    { True if the note source currently exists. }
    function Exists(const AId: string): Boolean;
  end;

  { Converts AsciiDoc source to HTML. The default adapter shells out to the
    `asciidoctor` binary. }
  IAsciiDocRenderer = interface
    { Returns the rendered HTML for a single source (used for incremental
      updates). }
    function Render(const ASource: string): string;
    { Render many sources at once. ASources[i] is rendered into AHtmls[i]
      (AHtmls is cleared and filled in the same order). Implementations may
      parallelise. Used for the initial full build. }
    procedure RenderMany(ASources: TList<string>; AHtmls: TList<string>);
  end;

  { Full-text index over rendered notes. }
  ISearchIndex = interface
    { Add or replace a note in the index. }
    procedure Upsert(ANote: TNote);
    { Remove a note from the index. }
    procedure Remove(const AId: string);
    { Clear the entire index. }
    procedure Clear;
    { Query and return ranked hits (caller owns the returned list + items). }
    function Search(const AQuery: string): TSearchHitList;
  end;

  { Notifies connected browsers that they should reload. }
  IReloadNotifier = interface
    procedure NotifyReload;
  end;

  { Launches an external editor on a note's source file. }
  IEditorLauncher = interface
    { Returns True if the editor was launched. }
    function LaunchEditor(const AAbsPath: string): Boolean;
  end;

  { Levelled diagnostic logging (cross-cutting; not strictly a domain port,
    but injected so the core stays free of a concrete logger). }
  ILogger = interface
    procedure Info(const AMsg: string);
    procedure Error(const AMsg: string);
  end;

  { Registry of every driven-port adapter, wired at the composition root.
    Passed as a single object because the native backend cannot pass four or
    more interface-typed values as separate call arguments. Holds the adapters
    as interface references so ARC keeps them alive for the registry's lifetime. }
  TPorts = class
  public
    Repo:     INoteRepository;
    Renderer: IAsciiDocRenderer;
    Index:    ISearchIndex;
    Reload:   IReloadNotifier;
    Editor:   IEditorLauncher;
    Log:      ILogger;
  end;

  { Null-object adapters. Used wherever a port is optional, so the core never
    has to test for nil (passing nil as an interface argument is unsupported). }
  TNullReloadNotifier = class(IReloadNotifier)
    procedure NotifyReload;
  end;

  TNullLogger = class(ILogger)
    procedure Info(const AMsg: string);
    procedure Error(const AMsg: string);
  end;

implementation

procedure TNullReloadNotifier.NotifyReload;
begin
end;

procedure TNullLogger.Info(const AMsg: string);
begin
end;

procedure TNullLogger.Error(const AMsg: string);
begin
end;

end.
