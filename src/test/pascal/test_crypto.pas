program crypto_test;
uses Luhmann.Crypto;
var Pass, Fail: Integer; r: string;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Pass:=Pass+1; WriteLn('  ok   ',AName) end
  else begin Fail:=Fail+1; WriteLn('  FAIL ',AName) end;
end;
begin
  Pass:=0; Fail:=0;

  // base64 of "Man" = "TWFu", "Ma"="TWE=", "M"="TQ=="
  Check('b64 Man', Base64Encode('Man') = 'TWFu');
  Check('b64 Ma', Base64Encode('Ma') = 'TWE=');
  Check('b64 M', Base64Encode('M') = 'TQ==');
  Check('b64 empty', Base64Encode('') = '');

  // SHA-1("abc") base64 = qZk+NkcGgWq6PiVxeFDCbJzQ2J0=
  r := Sha1Base64('abc');
  WriteLn('  sha1(abc) b64 = ', r);
  Check('sha1 abc', r = 'qZk+NkcGgWq6PiVxeFDCbJzQ2J0=');

  // WebSocket canonical handshake vector
  r := Sha1Base64('dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11');
  WriteLn('  ws-accept = ', r);
  Check('ws handshake', r = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=');

  WriteLn(''); WriteLn('PASS=',Pass,' FAIL=',Fail);
  if Fail>0 then Halt(1);
end.
