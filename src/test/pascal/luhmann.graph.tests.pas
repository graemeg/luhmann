{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Unit tests for TLinkGraph: out-link bookkeeping and the derived backlink
  index, including updates and note removal. }

unit Luhmann.Graph.Tests;

interface

uses
  blaise.testing, Luhmann.Graph;

type
  TLinkGraphTests = class(TTestCase)
  private
    G: TLinkGraph;
  protected
    procedure SetUp; override;
  published
    procedure TestBacklinks;
    procedure TestOutLinks;
    procedure TestBacklinksAfterEdit;
    procedure TestBacklinksAfterRemove;
  end;

implementation

uses
  Generics.Collections, Luhmann.Test.Support;

procedure TLinkGraphTests.SetUp;
begin
  G := TLinkGraph.Create();
  G.SetOutLinks('index.adoc', L('fruit/apple.adoc', 'fruit/orange.adoc'));
  G.SetOutLinks('fruit/apple.adoc', L('fruit/orange.adoc', ''));
end;

procedure TLinkGraphTests.TestBacklinks;
var
  bl: TList<string>;
begin
  bl := G.BacklinksOf('fruit/orange.adoc');
  AssertEquals('orange backlinks', 2, bl.Count);
  bl := G.BacklinksOf('fruit/apple.adoc');
  AssertEquals('apple backlinks', 1, bl.Count);
  AssertEquals('apple backlinked from index', 'index.adoc', bl.Get(0));
end;

procedure TLinkGraphTests.TestOutLinks;
begin
  AssertEquals('index outlinks', 2, G.OutLinksOf('index.adoc').Count);
end;

procedure TLinkGraphTests.TestBacklinksAfterEdit;
begin
  G.SetOutLinks('fruit/apple.adoc', L('', ''));
  AssertEquals('orange backlinks after apple edit', 1,
    G.BacklinksOf('fruit/orange.adoc').Count);
end;

procedure TLinkGraphTests.TestBacklinksAfterRemove;
begin
  G.RemoveNote('index.adoc');
  AssertEquals('apple backlinks after index delete', 0,
    G.BacklinksOf('fruit/apple.adoc').Count);
end;

initialization
  RegisterTest(TLinkGraphTests);

end.
