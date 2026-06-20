program json_test;
uses Luhmann.Json;
var Pass, Fail: Integer; w: TJsonWriter; s: string;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName,' got: ',s) end;
end;
begin
  Pass:=0; Fail:=0;
  Check('escape quote', JsonEscape('a"b\') = 'a\"b\\');

  // { "center": "apple.adoc", "nodes": [ {"id":"x","center":true} ], "n": 2 }
  w := TJsonWriter.Create();
  w.BeginObject();
    w.StrField('center', 'apple.adoc');
    w.Key('nodes');
    w.BeginArray();
      w.BeginObject();
        w.StrField('id', 'x');
        w.Key('center'); w.BoolValue(True);
      w.EndObject();
    w.EndArray();
    w.IntField('n', 2);
  w.EndObject();
  s := w.ToString();
  WriteLn('  json: ', s);
  Check('object built', s = '{"center":"apple.adoc","nodes":[{"id":"x","center":true}],"n":2}');
  w.Free();

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
