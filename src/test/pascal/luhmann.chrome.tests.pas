{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for luhmann.chrome: HTML escaping, note URLs and the page
  chrome wrapped around a rendered note body. }

unit Luhmann.Chrome.Tests;

interface

uses
  blaise.testing;

type
  TChromeTests = class(TTestCase)
  private
    function SamplePage: string;
  published
    procedure TestHtmlEscape;
    procedure TestNoteUrl;
    procedure TestPageStructure;
    procedure TestBacklinks;
    procedure TestTagChip;
    procedure TestAssets;
    procedure TestExternalLinkOpensNewTab;
    procedure TestInternalLinkUnchanged;
  end;

implementation

uses
  Generics.Collections, Luhmann.Chrome;

function TChromeTests.SamplePage: string;
var
  ids, titles, tags: TList<string>;
begin
  ids := TList<string>.Create(); ids.Add('index.adoc'); ids.Add('fruit/pear.adoc');
  titles := TList<string>.Create(); titles.Add('Home'); titles.Add('Pear');
  tags := TList<string>.Create(); tags.Add('fruit'); tags.Add('pome');
  Result := RenderPage('Apple', '<p>An apple.</p>', ids, titles, tags);
end;

procedure TChromeTests.TestHtmlEscape;
begin
  AssertEquals('escape', 'a&lt;b&gt;&amp;&quot;x', HtmlEscape('a<b>&"x'));
end;

procedure TChromeTests.TestNoteUrl;
begin
  AssertEquals('noteurl', '/fruit/apple.html', NoteUrl('fruit/apple.adoc'));
end;

procedure TChromeTests.TestPageStructure;
var
  page: string;
begin
  page := SamplePage();
  AssertContains('doctype', '<!DOCTYPE html>', page);
  AssertContains('title', '<title>Apple</title>', page);
  AssertContains('body content', '<p>An apple.</p>', page);
end;

procedure TChromeTests.TestBacklinks;
var
  page: string;
begin
  page := SamplePage();
  AssertContains('backlinks header', 'Backlinks', page);
  AssertContains('backlink to index', 'href="/index.html"', page);
  AssertContains('backlink to pear', 'href="/fruit/pear.html"', page);
end;

procedure TChromeTests.TestTagChip;
begin
  AssertContains('tag chip', '#fruit', SamplePage());
end;

procedure TChromeTests.TestAssets;
var
  page: string;
begin
  page := SamplePage();
  AssertContains('css link', '/luhmann.css', page);
  AssertContains('js script', '/luhmann.js', page);
end;

{ External links in the note body open in a new tab; internal (relative)
  links do not. }
procedure TChromeTests.TestExternalLinkOpensNewTab;
var
  page: string;
begin
  page := RenderPage('Links',
    '<p><a href="https://example.com">ext</a> <a href="other.html">int</a></p>',
    nil, nil, nil);
  AssertContains('external link opens new tab',
    'target="_blank" rel="noopener" href="https://example.com"', page);
end;

procedure TChromeTests.TestInternalLinkUnchanged;
var
  page: string;
begin
  page := RenderPage('Links',
    '<p><a href="https://example.com">ext</a> <a href="other.html">int</a></p>',
    nil, nil, nil);
  AssertContains('internal link unchanged', '<a href="other.html">', page);
end;

initialization
  RegisterTest(TChromeTests);

end.
