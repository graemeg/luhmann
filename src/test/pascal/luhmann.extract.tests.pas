{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for luhmann.extract (title, tags and out-links parsed from
  AsciiDoc source) and the path helpers it relies on. }

unit Luhmann.Extract.Tests;

interface

uses
  blaise.testing;

type
  TExtractTests = class(TTestCase)
  published
    procedure TestTitle;
    procedure TestTagsLowercasedAndTrimmed;
    procedure TestOutLinksResolved;
    procedure TestNormaliseRef;
    procedure TestDirOf;
  end;

implementation

uses
  Generics.Collections, Luhmann.Extract, Luhmann.Util;

const
  SRC = '= Apple Title'#10':tags: Fruit, Pome , edible'#10#10'Body text.'#10
      + 'See xref:orange.adoc[Orange] and link:../veg/carrot.adoc[Carrot].'#10
      + 'External xref:fruit/apple.adoc[Apple] from root.';

procedure TExtractTests.TestTitle;
begin
  AssertEquals('title', 'Apple Title', ExtractTitle(SRC));
end;

procedure TExtractTests.TestTagsLowercasedAndTrimmed;
var
  tags: TList<string>;
begin
  tags := ExtractTags(SRC);
  AssertEquals('tag count', 3, tags.Count);
  AssertEquals('tag 0', 'fruit', tags.Get(0));
  AssertEquals('tag 1', 'pome', tags.Get(1));
  AssertEquals('tag 2', 'edible', tags.Get(2));
end;

procedure TExtractTests.TestOutLinksResolved;
var
  links: TList<string>;
begin
  links := ExtractOutLinks(SRC, 'fruit');
  AssertTrue('orange resolved', links.IndexOf('fruit/orange.adoc') >= 0);
  AssertTrue('carrot via .. resolved', links.IndexOf('veg/carrot.adoc') >= 0);
end;

procedure TExtractTests.TestNormaliseRef;
begin
  AssertEquals('simple', 'fruit/orange.adoc', NormaliseRef('fruit', 'orange.adoc'));
  AssertEquals('..', 'a/c.adoc', NormaliseRef('a/b', '../c.adoc'));
  AssertEquals('root base', 'index.adoc', NormaliseRef('', 'index.adoc'));
  AssertEquals('dot', 'a/x.adoc', NormaliseRef('a', './x.adoc'));
end;

procedure TExtractTests.TestDirOf;
begin
  AssertEquals('nested', 'a/b', DirOf('a/b/c.adoc'));
  AssertEquals('flat', '', DirOf('x.adoc'));
end;

initialization
  RegisterTest(TExtractTests);

end.
