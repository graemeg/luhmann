{
  Luhmann - a Zettelkasten web server.
  SPDX-License-Identifier: MIT

  luhmann.libc - thin FFI bindings to the C standard library and the POSIX
  sockets API, plus a few byte/string bridging helpers.  This is the only unit
  that talks to libc directly; everything above it works in Blaise terms.

  A follow-up task moves the socket portion into the Blaise stdlib as a proper
  networking unit.
}
unit Luhmann.Libc;

interface

const
  { socket(2) address families and types }
  AF_INET      = 2;
  SOCK_STREAM  = 1;

  { setsockopt(2) }
  SOL_SOCKET   = 1;
  SO_REUSEADDR = 2;

  { special addresses }
  INADDR_ANY      = 0;        { 0.0.0.0 — bind all interfaces }
  INADDR_LOOPBACK = 16777343; { 127.0.0.1 in network byte order (htonl(0x7f000001)) }

type
  { struct sockaddr_in, Linux x86_64 layout — exactly 16 bytes.
    sin_addr and sin_port are in network byte order. }
  TSockAddrIn = record
    sin_family: UInt16;
    sin_port:   UInt16;
    sin_addr:   UInt32;
    sin_zero:   array[0..7] of Byte;
  end;

{ --- raw libc / syscall bindings --- }

function c_socket(Domain, AType, Protocol: Integer): Integer;
  external name 'socket';
function c_bind(Fd: Integer; Addr: Pointer; AddrLen: Integer): Integer;
  external name 'bind';
function c_listen(Fd, Backlog: Integer): Integer;
  external name 'listen';
function c_accept(Fd: Integer; Addr: Pointer; AddrLen: Pointer): Integer;
  external name 'accept';
function c_setsockopt(Fd, Level, OptName: Integer; OptVal: Pointer; OptLen: Integer): Integer;
  external name 'setsockopt';
function c_recv(Fd: Integer; Buf: Pointer; Len: Int64; Flags: Integer): Int64;
  external name 'recv';
function c_send(Fd: Integer; Buf: Pointer; Len: Int64; Flags: Integer): Int64;
  external name 'send';
function c_read(Fd: Integer; Buf: Pointer; Count: Int64): Int64;
  external name 'read';
function c_write(Fd: Integer; Buf: Pointer; Count: Int64): Int64;
  external name 'write';
function c_close(Fd: Integer): Integer;
  external name 'close';
function c_htons(HostShort: UInt16): UInt16;
  external name 'htons';
function c_shutdown(Fd, How: Integer): Integer;
  external name 'shutdown';

{ --- convenience helpers (Blaise-level) --- }

{ Open a TCP server socket bound to 127.0.0.1:APort and start listening.
  Returns the listening fd, or -1 on failure. }
function ListenLocal(APort: UInt16; ABacklog: Integer): Integer;

{ Send an entire Blaise string over a connected socket, looping until all
  bytes are written.  Returns True on success. }
function SendStr(Fd: Integer; const S: string): Boolean;

{ Convert N bytes at Buf into a Blaise string (treated as raw UTF-8). }
function BytesToStr(Buf: Pointer; N: Integer): string;

implementation

uses
  StrUtils;

function ListenLocal(APort: UInt16; ABacklog: Integer): Integer;
var
  Fd, One, I: Integer;
  Addr: TSockAddrIn;
begin
  Fd := c_socket(AF_INET, SOCK_STREAM, 0);
  if Fd < 0 then
  begin
    Result := -1;
    Exit;
  end;

  One := 1;
  c_setsockopt(Fd, SOL_SOCKET, SO_REUSEADDR, @One, 4);

  Addr.sin_family := AF_INET;
  Addr.sin_port   := c_htons(APort);
  Addr.sin_addr   := INADDR_LOOPBACK;  { localhost only — no external exposure }
  for I := 0 to 7 do
    Addr.sin_zero[I] := 0;

  if c_bind(Fd, @Addr, 16) <> 0 then
  begin
    c_close(Fd);
    Result := -1;
    Exit;
  end;

  if c_listen(Fd, ABacklog) <> 0 then
  begin
    c_close(Fd);
    Result := -1;
    Exit;
  end;

  Result := Fd;
end;

function SendStr(Fd: Integer; const S: string): Boolean;
var
  Total, N: Integer;
  P: PChar;
begin
  Total := Length(S);
  if Total = 0 then
  begin
    Result := True;
    Exit;
  end;
  P := PChar(S);
  while Total > 0 do
  begin
    N := c_send(Fd, P, Total, 0);
    if N <= 0 then
    begin
      Result := False;
      Exit;
    end;
    P := P + N;
    Total := Total - N;
  end;
  Result := True;
end;

function BytesToStr(Buf: Pointer; N: Integer): string;
var
  P: PChar;
  I: Integer;
  SB: TStringBuilder;
begin
  if N <= 0 then
  begin
    Result := '';
    Exit;
  end;
  P := Buf;
  SB := TStringBuilder.Create();
  for I := 0 to N - 1 do
    SB.AppendByte(Byte(P[I]));
  Result := SB.ToString();
  SB.Free();
end;

end.
