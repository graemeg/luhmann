{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.crypto - SHA-1 and Base64, the minimum needed for the WebSocket
  opening handshake (Sec-WebSocket-Accept = base64(sha1(key + GUID))).  Not
  intended as general-purpose crypto.

  NB: shifts and 'not' are not masked to 32 bits by the backend, so every
  32-bit operation is wrapped through Mask32 / explicit 'and $FFFFFFFF'.
}
unit Luhmann.Crypto;

interface

uses
  Classes;

{ Lower-case hex is not produced; returns the 20 raw SHA-1 bytes as a string. }
function Sha1(const AData: string): string;

{ Standard Base64 of the raw bytes in S. }
function Base64Encode(const S: string): string;

{ Convenience: base64(sha1(S)). }
function Sha1Base64(const AData: string): string;

implementation

const
  MASK32 = $FFFFFFFF;

function Rotl32(V: UInt32; ABits: Integer): UInt32;
begin
  Result := ((V shl ABits) or (V shr (32 - ABits))) and MASK32;
end;

function Sha1(const AData: string): string;
var
  H0, H1, H2, H3, H4: UInt32;
  MsgLen, TotalBits: Int64;
  PadLen, I, T, ChunkStart, NumChunks, C: Integer;
  Msg: array[0..63] of Byte;     { current 64-byte chunk }
  W: array[0..79] of UInt32;
  A, B, Cc, D, E, F, K, Temp: UInt32;
  PData: string;
  SB, OutSB: TStringBuilder;
begin
  { Build the padded message as a byte string:
    original || 0x80 || 0x00... || 64-bit big-endian bit length.
    AppendByte guarantees raw single bytes (there is no Chr in this dialect and
    string '+' of a multi-byte value would corrupt the digest). }
  MsgLen := Length(AData);
  TotalBits := MsgLen * 8;

  { number of zero bytes so that (len + 1 + pad + 8) is a multiple of 64 }
  PadLen := 56 - ((MsgLen + 1) mod 64);
  if PadLen < 0 then
    PadLen := PadLen + 64;

  SB := TStringBuilder.Create();
  SB.Append(AData);
  SB.AppendByte(128);
  for I := 1 to PadLen do
    SB.AppendByte(0);
  for I := 7 downto 0 do
    SB.AppendByte((TotalBits shr (I * 8)) and $FF);
  PData := SB.ToString();
  SB.Free();

  H0 := $67452301;
  H1 := $EFCDAB89;
  H2 := $98BADCFE;
  H3 := $10325476;
  H4 := $C3D2E1F0;

  NumChunks := Length(PData) div 64;
  for C := 0 to NumChunks - 1 do
  begin
    ChunkStart := C * 64;
    for I := 0 to 63 do
      Msg[I] := Byte(PData[ChunkStart + I]);

    for T := 0 to 15 do
      W[T] := ((UInt32(Msg[T * 4]) shl 24) or
               (UInt32(Msg[T * 4 + 1]) shl 16) or
               (UInt32(Msg[T * 4 + 2]) shl 8) or
                UInt32(Msg[T * 4 + 3])) and MASK32;
    for T := 16 to 79 do
      W[T] := Rotl32((W[T-3] xor W[T-8] xor W[T-14] xor W[T-16]), 1);

    A := H0; B := H1; Cc := H2; D := H3; E := H4;

    for T := 0 to 79 do
    begin
      if T < 20 then
      begin
        F := (B and Cc) or ((not B) and D);
        K := $5A827999;
      end
      else if T < 40 then
      begin
        F := B xor Cc xor D;
        K := $6ED9EBA1;
      end
      else if T < 60 then
      begin
        F := (B and Cc) or (B and D) or (Cc and D);
        K := $8F1BBCDC;
      end
      else
      begin
        F := B xor Cc xor D;
        K := $CA62C1D6;
      end;
      F := F and MASK32;
      Temp := (Rotl32(A, 5) + F + E + K + W[T]) and MASK32;
      E := D;
      D := Cc;
      Cc := Rotl32(B, 30);
      B := A;
      A := Temp;
    end;

    H0 := (H0 + A) and MASK32;
    H1 := (H1 + B) and MASK32;
    H2 := (H2 + Cc) and MASK32;
    H3 := (H3 + D) and MASK32;
    H4 := (H4 + E) and MASK32;
  end;

  { Emit 20 raw bytes, big-endian. }
  OutSB := TStringBuilder.Create();
  OutSB.AppendByte((H0 shr 24) and $FF); OutSB.AppendByte((H0 shr 16) and $FF);
  OutSB.AppendByte((H0 shr 8) and $FF);  OutSB.AppendByte(H0 and $FF);
  OutSB.AppendByte((H1 shr 24) and $FF); OutSB.AppendByte((H1 shr 16) and $FF);
  OutSB.AppendByte((H1 shr 8) and $FF);  OutSB.AppendByte(H1 and $FF);
  OutSB.AppendByte((H2 shr 24) and $FF); OutSB.AppendByte((H2 shr 16) and $FF);
  OutSB.AppendByte((H2 shr 8) and $FF);  OutSB.AppendByte(H2 and $FF);
  OutSB.AppendByte((H3 shr 24) and $FF); OutSB.AppendByte((H3 shr 16) and $FF);
  OutSB.AppendByte((H3 shr 8) and $FF);  OutSB.AppendByte(H3 and $FF);
  OutSB.AppendByte((H4 shr 24) and $FF); OutSB.AppendByte((H4 shr 16) and $FF);
  OutSB.AppendByte((H4 shr 8) and $FF);  OutSB.AppendByte(H4 and $FF);
  Result := OutSB.ToString();
  OutSB.Free();
end;

const
  B64_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function B64Char(AIndex: Integer): string;
begin
  Result := Copy(B64_ALPHA, AIndex, 1);
end;

function Base64Encode(const S: string): string;
var
  I, N: Integer;
  B0, B1, B2: Integer;
  Triple: Integer;
begin
  Result := '';
  N := Length(S);
  I := 0;
  while I < N do
  begin
    B0 := Byte(S[I]);
    if I + 1 < N then B1 := Byte(S[I+1]) else B1 := 0;
    if I + 2 < N then B2 := Byte(S[I+2]) else B2 := 0;
    Triple := (B0 shl 16) or (B1 shl 8) or B2;

    Result := Result + B64Char((Triple shr 18) and $3F);
    Result := Result + B64Char((Triple shr 12) and $3F);
    if I + 1 < N then
      Result := Result + B64Char((Triple shr 6) and $3F)
    else
      Result := Result + '=';
    if I + 2 < N then
      Result := Result + B64Char(Triple and $3F)
    else
      Result := Result + '=';
    I := I + 3;
  end;
end;

function Sha1Base64(const AData: string): string;
begin
  Result := Base64Encode(Sha1(AData));
end;

end.
