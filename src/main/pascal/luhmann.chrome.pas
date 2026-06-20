{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.chrome - wraps rendered note body HTML in the common page chrome
  (header, brand, search box, graph link) and appends a Backlinks section.
  Built by templated string assembly rather than DOM parsing, so no HTML
  parser is required.

  HTML escaping here is minimal and applied only to text we inject (titles,
  link labels); the note body is already valid HTML from asciidoctor and is
  emitted verbatim.
}
unit Luhmann.Chrome;

interface

uses
  Classes;

{ Escape the five XML/HTML special characters in a text value. }
function HtmlEscape(const S: string): string;

{ Build a full HTML page: chrome + body + backlinks panel.
  ATitle        - note title (escaped)
  ABodyHtml     - rendered body HTML (verbatim)
  ABacklinkIds  - note ids linking to this note (each rendered as a link)
  ABacklinkTitles - parallel list of titles for ABacklinkIds
  ATags         - tags for this note }
function RenderPage(const ATitle, ABodyHtml: string;
                    ABacklinkIds, ABacklinkTitles, ATags: TStringList): string;

{ Build the search results page. }
function RenderSearchPage(const AQuery: string;
                          AResultIds, AResultTitles, AResultSnippets: TStringList): string;

{ Convert a note id (foo/bar.adoc) to its served URL (/foo/bar.html). }
function NoteUrl(const AId: string): string;

implementation

uses
  StrUtils,
  Luhmann.Util,
  Luhmann.Model;

function HtmlEscape(const S: string): string;
var
  SB: TStringBuilder;
  I, N: Integer;
  B: Byte;
begin
  SB := TStringBuilder.Create();
  N := Length(S);
  I := 0;
  while I < N do
  begin
    B := Byte(S[I]);
    if B = 38 then SB.Append('&amp;')        { & }
    else if B = 60 then SB.Append('&lt;')    { < }
    else if B = 62 then SB.Append('&gt;')    { > }
    else if B = 34 then SB.Append('&quot;')  { " }
    else if B = 39 then SB.Append('&#39;')   { ' }
    else SB.AppendByte(B);
    I := I + 1;
  end;
  Result := SB.ToString();
  SB.Free();
end;

function NoteUrl(const AId: string): string;
begin
  Result := '/' + SourceToHtml(AId);
end;

function PageHead(const ATitle: string): string;
begin
  Result :=
    '<!DOCTYPE html><html><head>' +
    '<meta charset="UTF-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">' +
    '<link rel="icon" href="/favicon.svg">' +
    '<link rel="stylesheet" href="/luhmann.css">' +
    '<title>' + HtmlEscape(ATitle) + '</title>' +
    '</head><body>';
end;

function ChromeHeader: string;
begin
  Result :=
    '<div class="luh-header">' +
      '<div class="luh-brand"><a href="/">Luhmann</a></div>' +
      '<div class="luh-nav"><a href="/graph">Graph</a> <a href="/tags">Tags</a>' +
      ' <a href="/broken">Broken</a></div>' +
      '<div class="luh-spacer"></div>' +
      '<form class="luh-search" method="GET" action="/search">' +
        '<input name="q" placeholder="Search...">' +
      '</form>' +
    '</div>';
end;

function PageFoot: string;
begin
  Result := '<script src="/luhmann.js"></script></body></html>';
end;

function RenderTagChips(ATags: TStringList): string;
var
  SB: TStringBuilder;
  I: Integer;
  Tag: string;
begin
  if (ATags = nil) or (ATags.Count = 0) then
  begin
    Result := '';
    Exit;
  end;
  SB := TStringBuilder.Create();
  SB.Append('<div class="luh-tags">');
  for I := 0 to ATags.Count - 1 do
  begin
    Tag := ATags.Get(I);
    SB.Append('<a class="luh-tag" href="/tags/' + HtmlEscape(Tag) + '">#' +
              HtmlEscape(Tag) + '</a> ');
  end;
  SB.Append('</div>');
  Result := SB.ToString();
  SB.Free();
end;

function RenderBacklinks(AIds, ATitles: TStringList): string;
var
  SB: TStringBuilder;
  I: Integer;
  Title: string;
begin
  SB := TStringBuilder.Create();
  SB.Append('<div class="luh-backlinks"><h3>Backlinks</h3>');
  if (AIds = nil) or (AIds.Count = 0) then
    SB.Append('<p class="luh-none">No backlinks</p>')
  else
  begin
    SB.Append('<ul>');
    for I := 0 to AIds.Count - 1 do
    begin
      if (ATitles <> nil) and (I < ATitles.Count) then
        Title := ATitles.Get(I)
      else
        Title := AIds.Get(I);
      SB.Append('<li><a href="' + NoteUrl(AIds.Get(I)) + '">' +
                HtmlEscape(Title) + '</a></li>');
    end;
    SB.Append('</ul>');
  end;
  SB.Append('</div>');
  Result := SB.ToString();
  SB.Free();
end;

{ Make external links open in a new tab. Internal note links (from xref:) render
  as relative '.html' hrefs, so only anchors whose href has an http(s) scheme are
  rewritten; rel="noopener" is added for safety. }
function ExternaliseLinks(const AHtml: string): string;
begin
  Result := ReplaceAll(AHtml, '<a href="http',
                              '<a target="_blank" rel="noopener" href="http');
end;

function RenderPage(const ATitle, ABodyHtml: string;
  ABacklinkIds, ABacklinkTitles, ATags: TStringList): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create();
  SB.Append(PageHead(ATitle));
  SB.Append(ChromeHeader());
  SB.Append('<div class="luh-body"><div class="luh-content">');
  SB.Append(RenderTagChips(ATags));
  SB.Append(ExternaliseLinks(ABodyHtml));
  SB.Append(RenderBacklinks(ABacklinkIds, ABacklinkTitles));
  SB.Append('</div></div>');
  SB.Append(PageFoot());
  Result := SB.ToString();
  SB.Free();
end;

function RenderSearchPage(const AQuery: string;
  AResultIds, AResultTitles, AResultSnippets: TStringList): string;
var
  SB: TStringBuilder;
  I: Integer;
  Title, Snippet: string;
begin
  SB := TStringBuilder.Create();
  SB.Append(PageHead('Search: ' + AQuery));
  SB.Append(ChromeHeader());
  SB.Append('<div class="luh-body"><div class="luh-content">');
  SB.Append('<h1>Search results: ' + HtmlEscape(AQuery) + '</h1>');
  if (AResultIds = nil) or (AResultIds.Count = 0) then
    SB.Append('<p class="luh-none">No results</p>')
  else
    for I := 0 to AResultIds.Count - 1 do
    begin
      if (AResultTitles <> nil) and (I < AResultTitles.Count) then
        Title := AResultTitles.Get(I)
      else
        Title := AResultIds.Get(I);
      if (AResultSnippets <> nil) and (I < AResultSnippets.Count) then
        Snippet := AResultSnippets.Get(I)
      else
        Snippet := '';
      SB.Append('<div class="luh-result">');
      SB.Append('<a class="luh-result-title" href="' + NoteUrl(AResultIds.Get(I)) +
                '">' + HtmlEscape(Title) + '</a>');
      SB.Append('<div class="luh-result-snippet">' + HtmlEscape(Snippet) + '</div>');
      SB.Append('</div>');
    end;
  SB.Append('</div></div>');
  SB.Append(PageFoot());
  Result := SB.ToString();
  SB.Free();
end;

end.
