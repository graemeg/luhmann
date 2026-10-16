{ Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  Small helpers shared by the test units. }

unit Luhmann.Test.Support;

interface

uses
  Generics.Collections;

{ A list of up to two strings; empty arguments are skipped. }
function L(const A, B: string): TList<string>;

implementation

function L(const A, B: string): TList<string>;
begin
  Result := TList<string>.Create();
  if A <> '' then Result.Add(A);
  if B <> '' then Result.Add(B);
end;

end.
