program http_test;
uses Net.Http.Server;
type
  TMyHandler = class(IRequestHandler)
    procedure Handle(ARequest: THttpRequest; AResponse: THttpResponse);
  end;
procedure TMyHandler.Handle(ARequest: THttpRequest; AResponse: THttpResponse);
begin
  if ARequest.Path = '/hello' then
    AResponse.SetText(200, 'text/plain', 'Hello from Blaise! q=' + ARequest.QueryParam('q'))
  else
    AResponse.SetText(404, 'text/plain', 'not found: ' + ARequest.Path);
end;
var
  Srv: THttpServer;
  H: IRequestHandler;
  i: Integer;
begin
  Srv := THttpServer.Create(19097);
  if not Srv.Start() then begin WriteLn('start failed'); Halt(1) end;
  H := TMyHandler.Create();
  WriteLn('READY');
  for i := 1 to 3 do
    Srv.ServeOnce(H);
  WriteLn('DONE');
end.
