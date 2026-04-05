program rn;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Types(* for tstringdynarray *), IniFiles, BaseUnix, Unix, Sockets, StrUtils,
  dns_packet, v6alt_codec;

const
  BUF_SIZE = 4096;
  DEFAULT_CONFIG_FILE = '/etc/rn.conf';
  DEFAULT_LOG_FILE = '/var/log/rn.log';
  DEFAULT_BIND4 = '127.0.0.1';
  DEFAULT_BIND6 = '::1';
  ANY_BIND4 = '0.0.0.0';
  ANY_BIND6 = '::';
  DEFAULT_TTL = 60;

type
  TStringArray = array of AnsiString;
  TSockAddrBuf = packed array[0..127] of Byte;
  TServerKind = (skIPv4, skIPv6);

  TUpstream = record
    Host: AnsiString;
    Port: Word;
    Kind: TServerKind;
    Addr4: TInetSockAddr;
    Addr6: TInetSockAddr6;
  end;
  TUpstreamArray = array of TUpstream;

  TListener = record
    Sock: LongInt;
    Kind: TServerKind;
    AddrText: AnsiString;
    Port: Word;
  end;
  TListenerArray = array of TListener;

var
  ListenPort: Word = 53;
  Upstreams: TUpstreamArray;
  Listeners: TListenerArray;
  Bind4List: TStringArray;
  Bind6List: TStringArray;
  LogFilePath: AnsiString = DEFAULT_LOG_FILE;
  LogQueries: Boolean = False;

procedure SetSingleString(var Arr: TStringArray; const S: AnsiString);
begin
  SetLength(Arr, 1);
  Arr[0] := Trim(S);
end;

procedure AddString(var Arr: TStringArray; const S: AnsiString);
var
  N: Integer;
  T: AnsiString;
begin
  T := Trim(S);
  if T = '' then
    Exit;
  N := Length(Arr);
  SetLength(Arr, N + 1);
  Arr[N] := T;
end;


procedure SplitCSVToArray(const S: AnsiString; var Arr: TStringArray);
var
  Parts: TStringDynArray;
  I: Integer;
  Item: AnsiString;
begin
  Parts := SplitString(S, ',');
  for I := 0 to High(Parts) do
  begin
    Item := Trim(Parts[I]);
    if Item <> '' then
      AddString(Arr, Item);
  end;
end;

procedure SetListenLocal;
begin
  SetSingleString(Bind4List, DEFAULT_BIND4);
  SetSingleString(Bind6List, DEFAULT_BIND6);
end;

procedure SetListenAll;
begin
  SetSingleString(Bind4List, ANY_BIND4);
  SetSingleString(Bind6List, ANY_BIND6);
end;

procedure LogLine(const Msg: AnsiString; ToStdErr: Boolean = False);
var
  F: TextFile;
  Line: AnsiString;
begin
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ' + Msg;
  if ToStdErr then
    Writeln(StdErr, Line)
  else
    Writeln(Line);

  if LogFilePath <> '' then
  begin
    AssignFile(F, LogFilePath);
    {$I-}
    if FileExists(LogFilePath) then
      Append(F)
    else
      Rewrite(F);
    if IOResult = 0 then
    begin
      Writeln(F, Line);
      CloseFile(F);
    end;
    {$I+}
  end;
end;

procedure Usage;
begin
  Writeln('rn - local .v6.alt DNS responder + UDP forwarder');
  Writeln('');
  Writeln('Usage:');
  Writeln('  rn <port> <upstream[:port]> [upstream[:port] ...] [options]');
  Writeln('  rn -c [config-file] [options]');
  Writeln('  rn -h | --help');
  Writeln('');
  Writeln('Options:');
  Writeln('  --listen-all        Bind IPv4 to 0.0.0.0 and IPv6 to ::');
  Writeln('  --bind4=<addr>      Add one IPv4 bind address (can be repeated)');
  Writeln('  --bind6=<addr>      Add one IPv6 bind address (can be repeated)');
  Writeln('  --log-file=<path>   Override log file path');
  Writeln('  --log-queries       Enable query logging');
  Writeln('  --no-log-queries    Disable query logging');
  Writeln('');
  Writeln('Config file keys:');
  Writeln('  [server]');
  Writeln('    port=53');
  Writeln('    listen_mode=local|all');
  Writeln('    bind_ipv4=127.0.0.1, 10.0.0.5');
  Writeln('    bind_ipv6=::1, 200:ffff::1');
  Writeln('  [upstreams]');
  Writeln('    dns=1.1.1.1, 8.8.8.8, [2606:4700:4700::1111]:53');
  Writeln('  [logging]');
  Writeln('    file=/var/log/rn.log');
  Writeln('    queries=true|false');
end;

function ParsePort(const S: AnsiString; out P: Word): Boolean;
var
  N: Integer;
begin
  Result := TryStrToInt(S, N) and (N >= 1) and (N <= 65535);
  if Result then
    P := N;
end;

function ParseBoolText(const S: string; Default: Boolean): Boolean;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  if (L = '1') or (L = 'true') or (L = 'yes') or (L = 'on') then
    Exit(True);
  if (L = '0') or (L = 'false') or (L = 'no') or (L = 'off') then
    Exit(False);
  Result := Default;
end;

function ParseUpstreamSpec(const Spec: AnsiString; out U: TUpstream): Boolean;
var
  HostPart, PortPart: AnsiString;
  P: SizeInt;
begin
  Result := False;
  FillChar(U, SizeOf(U), 0);
  U.Port := 53;

  if (Spec <> '') and (Spec[1] = '[') then
  begin
    P := Pos(']', Spec);
    if P <= 0 then Exit;
    HostPart := Copy(Spec, 2, P - 2);
    if (P < Length(Spec)) and (Spec[P + 1] = ':') then
      PortPart := Copy(Spec, P + 2, MaxInt);
  end
  else
  begin
    if (Pos(':', Spec) > 0) and (Pos(':', Copy(Spec, Pos(':', Spec) + 1, MaxInt)) > 0) then
      HostPart := Spec
    else if Pos(':', Spec) > 0 then
    begin
      P := Pos(':', Spec);
      HostPart := Copy(Spec, 1, P - 1);
      PortPart := Copy(Spec, P + 1, MaxInt);
    end
    else
      HostPart := Spec;
  end;

  if HostPart = '' then
    Exit;
  if (PortPart <> '') and not ParsePort(PortPart, U.Port) then
    Exit;

  U.Host := HostPart;
  if Pos(':', HostPart) > 0 then
  begin
    U.Kind := skIPv6;
    FillChar(U.Addr6, SizeOf(U.Addr6), 0);
    U.Addr6.sin6_family := AF_INET6;
    U.Addr6.sin6_port := htons(U.Port);
    U.Addr6.sin6_addr := StrToHostAddr6(HostPart);
  end
  else
  begin
    U.Kind := skIPv4;
    FillChar(U.Addr4, SizeOf(U.Addr4), 0);
    U.Addr4.sin_family := AF_INET;
    U.Addr4.sin_port := htons(U.Port);
    U.Addr4.sin_addr := StrToNetAddr(HostPart);
  end;

  Result := True;
end;

procedure AddUpstream(const Spec: AnsiString);
var
  U: TUpstream;
  N: Integer;
begin
  if not ParseUpstreamSpec(Spec, U) then
  begin
    LogLine('Invalid upstream: ' + Spec, True);
    Halt(1);
  end;
  N := Length(Upstreams);
  SetLength(Upstreams, N + 1);
  Upstreams[N] := U;
end;

function BindIPv4(const IP: AnsiString; Port: Word; out Sock: LongInt): Boolean;
var
  Addr: TInetSockAddr;
  Opt, E: LongInt;
begin
  Result := False;
  Sock := fpsocket(AF_INET, SOCK_DGRAM, 0);
  if Sock < 0 then
  begin
    E := fpgeterrno;
    LogLine('IPv4 socket() failed: ' + IntToStr(E) + ' ' + SysErrorMessage(E), True);
    Exit;
  end;

  Opt := 1;
  fpsetsockopt(Sock, SOL_SOCKET, SO_REUSEADDR, @Opt, SizeOf(Opt));

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(Port);
  Addr.sin_addr := StrToNetAddr(IP);

  if fpbind(Sock, @Addr, SizeOf(Addr)) <> 0 then
  begin
    E := fpgeterrno;
    LogLine('IPv4 bind(' + IP + ':' + IntToStr(Port) + ') failed: ' + IntToStr(E) + ' ' + SysErrorMessage(E), True);
    FpClose(Sock);
    Sock := -1;
    Exit;
  end;

  Result := True;
end;

function BindIPv6(const IP: AnsiString; Port: Word; out Sock: LongInt): Boolean;
var
  Addr: TInetSockAddr6;
  Opt, E: LongInt;
begin
  Result := False;
  Sock := fpsocket(AF_INET6, SOCK_DGRAM, 0);
  if Sock < 0 then
  begin
    E := fpgeterrno;
    LogLine('IPv6 socket() failed: ' + IntToStr(E) + ' ' + SysErrorMessage(E), True);
    Exit;
  end;

  Opt := 1;
  fpsetsockopt(Sock, SOL_SOCKET, SO_REUSEADDR, @Opt, SizeOf(Opt));
  {$ifdef IPV6_V6ONLY}
  fpsetsockopt(Sock, IPPROTO_IPV6, IPV6_V6ONLY, @Opt, SizeOf(Opt));
  {$endif}

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin6_family := AF_INET6;
  Addr.sin6_port := htons(Port);
  Addr.sin6_addr := StrToHostAddr6(IP);

  if fpbind(Sock, @Addr, SizeOf(Addr)) <> 0 then
  begin
    E := fpgeterrno;
    LogLine('IPv6 bind([' + IP + ']:' + IntToStr(Port) + ') failed: ' + IntToStr(E) + ' ' + SysErrorMessage(E), True);
    FpClose(Sock);
    Sock := -1;
    Exit;
  end;

  Result := True;
end;

procedure AddListener(Kind: TServerKind; const AddrText: AnsiString; Port: Word; Sock: LongInt);
var
  N: Integer;
begin
  N := Length(Listeners);
  SetLength(Listeners, N + 1);
  Listeners[N].Sock := Sock;
  Listeners[N].Kind := Kind;
  Listeners[N].AddrText := AddrText;
  Listeners[N].Port := Port;
end;

procedure SetupListeners;
var
  I: Integer;
  Sock: LongInt;
begin
  SetLength(Listeners, 0);
  for I := 0 to High(Bind4List) do
    if BindIPv4(Bind4List[I], ListenPort, Sock) then
      AddListener(skIPv4, Bind4List[I], ListenPort, Sock);
  for I := 0 to High(Bind6List) do
    if BindIPv6(Bind6List[I], ListenPort, Sock) then
      AddListener(skIPv6, Bind6List[I], ListenPort, Sock);

  if Length(Listeners) = 0 then
  begin
    LogLine('Could not bind any listening sockets on UDP port ' + IntToStr(ListenPort), True);
    Halt(1);
  end;
end;

procedure LoadConfig(const FileName: AnsiString);
var
  Ini: TIniFile;
  Values: TStringList;
  I: Integer;
  S, Key, ListenMode: String;
  Bind4Temp, Bind6Temp, DNSTemp: TStringArray;
begin
  if not FileExists(FileName) then
  begin
    LogLine('Config file not found: ' + FileName, True);
    Halt(1);
  end;

  Ini := TIniFile.Create(FileName);
  Values := TStringList.Create;
  SetLength(Bind4Temp, 0);
  SetLength(Bind6Temp, 0);
  SetLength(DNSTemp, 0);
  try
    ListenPort := Ini.ReadInteger('server', 'port', 53);

    ListenMode := LowerCase(Trim(Ini.ReadString('server', 'listen_mode', 'local')));
    if ListenMode = 'all' then
      SetListenAll
    else
      SetListenLocal;

    Ini.ReadSectionValues('server', Values);
    for I := 0 to Values.Count - 1 do
    begin
      Key := LowerCase(Trim(Values.Names[I]));
      S := Trim(Values.ValueFromIndex[I]);
      if S = '' then
        Continue;
      if Key = 'bind_ipv4' then
        SplitCSVToArray(S, Bind4Temp)
      else if Key = 'bind_ipv6' then
        SplitCSVToArray(S, Bind6Temp);
    end;

    if Length(Bind4Temp) > 0 then
      Bind4List := Copy(Bind4Temp, 0, Length(Bind4Temp));
    if Length(Bind6Temp) > 0 then
      Bind6List := Copy(Bind6Temp, 0, Length(Bind6Temp));

    LogFilePath := Trim(Ini.ReadString('logging', 'file', DEFAULT_LOG_FILE));
    LogQueries := ParseBoolText(Ini.ReadString('logging', 'queries', 'false'), False);

    Values.Clear;
    Ini.ReadSectionValues('upstreams', Values);
    for I := 0 to Values.Count - 1 do
    begin
      Key := LowerCase(Trim(Values.Names[I]));
      S := Trim(Values.ValueFromIndex[I]);
      if (Key = 'dns') and (S <> '') then
        SplitCSVToArray(S, DNSTemp);
    end;

    for I := 0 to High(DNSTemp) do
      AddUpstream(DNSTemp[I]);
  finally
    Values.Free;
    Ini.Free;
  end;
end;

function QTypeToText(QType: Word): string;
begin
  case QType of
    DNS_TYPE_A: Result := 'A';
    DNS_TYPE_AAAA: Result := 'AAAA';
    DNS_TYPE_PTR: Result := 'PTR';
  else
    Result := IntToStr(QType);
  end;
end;

function ForwardQuery(const Packet: array of Byte; PacketLen: Integer; out Reply: TBytes): Integer;
var
  I, S, R: Integer;
  FromBuf: TSockAddrBuf;
  AddrLen: TSockLen;
  TV: TTimeVal;
begin
  Result := 0;
  SetLength(Reply, 0);

  for I := 0 to High(Upstreams) do
  begin
    if Upstreams[I].Kind = skIPv4 then
      S := fpsocket(AF_INET, SOCK_DGRAM, 0)
    else
      S := fpsocket(AF_INET6, SOCK_DGRAM, 0);
    if S < 0 then
      Continue;

    TV.tv_sec := 2;
    TV.tv_usec := 0;
    fpsetsockopt(S, SOL_SOCKET, SO_RCVTIMEO, @TV, SizeOf(TV));
    fpsetsockopt(S, SOL_SOCKET, SO_SNDTIMEO, @TV, SizeOf(TV));

    if Upstreams[I].Kind = skIPv4 then
      R := fpsendto(S, @Packet[0], PacketLen, 0, @Upstreams[I].Addr4, SizeOf(Upstreams[I].Addr4))
    else
      R := fpsendto(S, @Packet[0], PacketLen, 0, @Upstreams[I].Addr6, SizeOf(Upstreams[I].Addr6));

    if R = PacketLen then
    begin
      SetLength(Reply, BUF_SIZE);
      AddrLen := SizeOf(FromBuf);
      R := fprecvfrom(S, @Reply[0], Length(Reply), 0, @FromBuf[0], @AddrLen);
      if R > 0 then
      begin
        SetLength(Reply, R);
        FpClose(S);
        Exit(R);
      end;
    end;

    FpClose(S);
  end;
end;

procedure SendResponse(Sock: LongInt; const PeerBuf: TSockAddrBuf; PeerLen: TSockLen;
  const Resp: TBytes; RespLen: Integer);
begin
  if RespLen > 0 then
    fpsendto(Sock, @Resp[0], RespLen, 0, @PeerBuf[0], PeerLen);
end;

procedure SendSimpleError(Sock: LongInt; const PeerBuf: TSockAddrBuf; PeerLen: TSockLen;
  const Query: array of Byte; QueryLen: Integer; RCode: Byte);
var
  ID, Flags: Word;
  Q: TDNSQuestion;
  Resp: TBytes;
  RespLen: Integer;
begin
  if ParseDNSQuestion(Query[0], QueryLen, ID, Flags, Q) then
  begin
    RespLen := BuildNoDataResponse(Query[0], QueryLen, Q, RCode, Resp);
    SendResponse(Sock, PeerBuf, PeerLen, Resp, RespLen);
  end;
end;

procedure HandleOne(Sock: LongInt; const ListenerDesc: AnsiString);
var
  PeerBuf: TSockAddrBuf;
  PeerLen: TSockLen;
  Buf: array[0..BUF_SIZE - 1] of Byte;
  N: Integer;
  ID, Flags: Word;
  Q: TDNSQuestion;
  IPv6: TIPv6Bytes;
  Resp: TBytes;
  RespLen: Integer;
  Forwarded: TBytes;
  PtrName: AnsiString;
begin
  PeerLen := SizeOf(PeerBuf);
  N := fprecvfrom(Sock, @Buf[0], SizeOf(Buf), 0, @PeerBuf[0], @PeerLen);
  if N <= 0 then
    Exit;

  if not ParseDNSQuestion(Buf[0], N, ID, Flags, Q) then
  begin
    LogLine('Malformed DNS packet on ' + ListenerDesc, True);
    SendSimpleError(Sock, PeerBuf, PeerLen, Buf, N, DNS_RCODE_SERVFAIL);
    Exit;
  end;

  if LogQueries then
    LogLine('Query ' + QTypeToText(Q.QType) + ' ' + Q.QName + ' via ' + ListenerDesc);

  if (Q.QClass = DNS_CLASS_IN) and IsV6AltName(Q.QName) then
  begin
    if TryDecodeV6AltHost(Q.QName, IPv6) then
    begin
      if Q.QType = DNS_TYPE_AAAA then
        RespLen := BuildAAAAResponse(Buf[0], N, Q, IPv6, DEFAULT_TTL, Resp)
      else
        RespLen := BuildNoDataResponse(Buf[0], N, Q, DNS_RCODE_NOERROR, Resp);
      SendResponse(Sock, PeerBuf, PeerLen, Resp, RespLen);
      if LogQueries then
        LogLine('Local AAAA ' + Q.QName + ' -> ' + IPv6BytesToText(IPv6));
      Exit;
    end
    else
    begin
      RespLen := BuildNoDataResponse(Buf[0], N, Q, DNS_RCODE_NXDOMAIN, Resp);
      SendResponse(Sock, PeerBuf, PeerLen, Resp, RespLen);
      if LogQueries then
        LogLine('NXDOMAIN ' + Q.QName);
      Exit;
    end;
  end;

  if (Q.QClass = DNS_CLASS_IN) and IsIP6ArpaName(Q.QName) then
  begin
    if TryParseIP6ArpaQName(Q.QName, IPv6) then
    begin
      PtrName := IPv6BytesToV6AltHost(IPv6);
      if Q.QType = DNS_TYPE_PTR then
        RespLen := BuildPTRResponse(Buf[0], N, Q, PtrName, DEFAULT_TTL, Resp)
      else
        RespLen := BuildNoDataResponse(Buf[0], N, Q, DNS_RCODE_NOERROR, Resp);
      SendResponse(Sock, PeerBuf, PeerLen, Resp, RespLen);
      if LogQueries then
        LogLine('Local PTR ' + IPv6BytesToText(IPv6) + ' -> ' + PtrName);
      Exit;
    end;
  end;

  if Length(Upstreams) > 0 then
  begin
    RespLen := ForwardQuery(Buf, N, Forwarded);
    if RespLen > 0 then
    begin
      SendResponse(Sock, PeerBuf, PeerLen, Forwarded, RespLen);
      if LogQueries then
        LogLine('Forwarded ' + QTypeToText(Q.QType) + ' ' + Q.QName);
      Exit;
    end;
  end;

  if LogQueries then
    LogLine('SERVFAIL ' + QTypeToText(Q.QType) + ' ' + Q.QName, True);
  SendSimpleError(Sock, PeerBuf, PeerLen, Buf, N, DNS_RCODE_SERVFAIL);
end;

procedure MainLoop;
var
  Readfds: TFDSet;
  MaxFD, R, I: LongInt;
begin
  while True do
  begin
    fpFD_ZERO(Readfds);
    MaxFD := -1;

    for I := 0 to High(Listeners) do
    begin
      fpFD_SET(Listeners[I].Sock, Readfds);
      if Listeners[I].Sock > MaxFD then
        MaxFD := Listeners[I].Sock;
    end;

    R := fpselect(MaxFD + 1, @Readfds, nil, nil, nil);
    if R <= 0 then
      Continue;

    for I := 0 to High(Listeners) do
      if fpFD_ISSET(Listeners[I].Sock, Readfds) <> 0 then
        HandleOne(Listeners[I].Sock, Listeners[I].AddrText + ':' + IntToStr(Listeners[I].Port));
  end;
end;

procedure PrintStartup;
var
  I: Integer;
begin
  for I := 0 to High(Listeners) do
    if Listeners[I].Kind = skIPv6 then
      LogLine('Listening on [' + Listeners[I].AddrText + ']:' + IntToStr(Listeners[I].Port))
    else
      LogLine('Listening on ' + Listeners[I].AddrText + ':' + IntToStr(Listeners[I].Port));

  if Length(Upstreams) > 0 then
  begin
    LogLine('Forwarding non-.v6.alt and non-ip6.arpa queries to:');
    for I := 0 to High(Upstreams) do
      if Upstreams[I].Kind = skIPv6 then
        LogLine('  [' + Upstreams[I].Host + ']:' + IntToStr(Upstreams[I].Port))
      else
        LogLine('  ' + Upstreams[I].Host + ':' + IntToStr(Upstreams[I].Port));
  end
  else
    LogLine('No upstreams configured; non-local queries will get SERVFAIL.');
end;

procedure ParseConfigMode(StartIndex: Integer; const ConfigFile: AnsiString);
var
  I: Integer;
  Arg: string;
  CliBind4Cleared, CliBind6Cleared: Boolean;
begin
  LoadConfig(ConfigFile);
  CliBind4Cleared := False;
  CliBind6Cleared := False;
  for I := StartIndex to ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--listen-all' then
    begin
      SetListenAll;
      CliBind4Cleared := False;
      CliBind6Cleared := False;
    end
    else if Copy(Arg, 1, 8) = '--bind4=' then
    begin
      if not CliBind4Cleared then
      begin
        SetLength(Bind4List, 0);
        CliBind4Cleared := True;
      end;
      AddString(Bind4List, Copy(Arg, 9, MaxInt));
    end
    else if Copy(Arg, 1, 8) = '--bind6=' then
    begin
      if not CliBind6Cleared then
      begin
        SetLength(Bind6List, 0);
        CliBind6Cleared := True;
      end;
      AddString(Bind6List, Copy(Arg, 9, MaxInt));
    end
    else if Copy(Arg, 1, 11) = '--log-file=' then
      LogFilePath := Copy(Arg, 12, MaxInt)
    else if Arg = '--log-queries' then
      LogQueries := True
    else if Arg = '--no-log-queries' then
      LogQueries := False
    else
    begin
      LogLine('Unknown option in config mode: ' + Arg, True);
      Halt(1);
    end;
  end;
end;

procedure ParseCommandMode;
var
  I: Integer;
  Arg: string;
  TmpPort: Word;
  CliBind4Cleared, CliBind6Cleared: Boolean;
begin
  if not ParsePort(ParamStr(1), TmpPort) then
  begin
    LogLine('First argument must be a port number, or use -c.', True);
    Usage;
    Halt(1);
  end;
  ListenPort := TmpPort;
  SetListenLocal;
  CliBind4Cleared := False;
  CliBind6Cleared := False;

  for I := 2 to ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--listen-all' then
    begin
      SetListenAll;
      CliBind4Cleared := False;
      CliBind6Cleared := False;
    end
    else if Copy(Arg, 1, 8) = '--bind4=' then
    begin
      if not CliBind4Cleared then
      begin
        SetLength(Bind4List, 0);
        CliBind4Cleared := True;
      end;
      AddString(Bind4List, Copy(Arg, 9, MaxInt));
    end
    else if Copy(Arg, 1, 8) = '--bind6=' then
    begin
      if not CliBind6Cleared then
      begin
        SetLength(Bind6List, 0);
        CliBind6Cleared := True;
      end;
      AddString(Bind6List, Copy(Arg, 9, MaxInt));
    end
    else if Copy(Arg, 1, 11) = '--log-file=' then
      LogFilePath := Copy(Arg, 12, MaxInt)
    else if Arg = '--log-queries' then
      LogQueries := True
    else if Arg = '--no-log-queries' then
      LogQueries := False
    else
      AddUpstream(Arg);
  end;

  if Length(Upstreams) = 0 then
  begin
    LogLine('Command-line mode requires at least one upstream server.', True);
    Halt(1);
  end;
end;

var
  ConfigFile: AnsiString;
  NextIndex: Integer;
begin
  SetLength(Upstreams, 0);
  SetLength(Listeners, 0);
  SetListenLocal;

  if ParamCount = 0 then
  begin
    Usage;
    Halt(1);
  end;

  if (ParamStr(1) = '-h') or (ParamStr(1) = '--help') then
  begin
    Usage;
    Halt(0);
  end;

  if ParamStr(1) = '-c' then
  begin
    if (ParamCount >= 2) and (Copy(ParamStr(2), 1, 2) <> '--') then
    begin
      ConfigFile := ParamStr(2);
      NextIndex := 3;
    end
    else
    begin
      ConfigFile := DEFAULT_CONFIG_FILE;
      NextIndex := 2;
    end;
    ParseConfigMode(NextIndex, ConfigFile);
  end
  else
    ParseCommandMode;

  SetupListeners;
  PrintStartup;
  MainLoop;
end.
