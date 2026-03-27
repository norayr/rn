program rn;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, IniFiles, BaseUnix, Unix, Sockets,
  dns_packet, v6alt_codec;

const
  BUF_SIZE = 4096;
  DEFAULT_CONFIG_FILE = '/etc/rn.conf';
  DEFAULT_BIND4 = '127.0.0.1';
  DEFAULT_BIND6 = '::1';
  ANY_BIND4 = '0.0.0.0';
  ANY_BIND6 = '::';

type
  TSockAddrBuf = packed array[0..127] of Byte;
  TServerKind = (skIPv4, skIPv6);

  TUpstream = record
    Host: AnsiString;
    Port: Word;
    Kind: TServerKind;
    Addr4: TInetSockAddr;
    Addr6: TInetSockAddr6;
  end;

var
  Sock4, Sock6: LongInt;
  ListenPort: Word = 53;
  Upstreams: array of TUpstream;
  Bind4: AnsiString = DEFAULT_BIND4;
  Bind6: AnsiString = DEFAULT_BIND6;

procedure Usage;
begin
  Writeln('rn - local .v6.alt DNS responder + optional UDP forwarder');
  Writeln('');
  Writeln('Usage:');
  Writeln('  rn <port> <upstream[:port]> [upstream[:port] ...] [options]');
  Writeln('  rn -c [config-file] [options]');
  Writeln('  rn -h | --help');
  Writeln('');
  Writeln('Options:');
  Writeln('  --listen-all        Bind IPv4 to 0.0.0.0 and IPv6 to ::');
  Writeln('  --bind4=<addr>      Bind IPv4 socket to this address');
  Writeln('  --bind6=<addr>      Bind IPv6 socket to this address');
  Writeln('');
  Writeln('Notes:');
  Writeln('  - In command-line mode, at least one upstream must be given.');
  Writeln('  - With -c, one optional config file path may be given.');
  Writeln('  - Command-line bind options override config file settings.');
  Writeln('  - If -c is used without a file name, the default config file is used:');
  Writeln('      ', DEFAULT_CONFIG_FILE);
  Writeln('');
  Writeln('Examples:');
  Writeln('  rn 53 1.1.1.1');
  Writeln('  rn 53 1.1.1.1 9.9.9.9 --listen-all');
  Writeln('  rn 5353 [2606:4700:4700::1111]:53 1.1.1.1:53 --bind4=0.0.0.0 --bind6=::');
  Writeln('  rn -c');
  Writeln('  rn -c ./rn.conf');
  Writeln('  rn -c ./rn.conf --listen-all');
  Writeln('');
  Writeln('Example config file:');
  Writeln('  [server]');
  Writeln('  port=53');
  Writeln('  listen_mode=local');
  Writeln('  ; listen_mode=all');
  Writeln('  ; bind_ipv4=127.0.0.1');
  Writeln('  ; bind_ipv6=::1');
  Writeln('');
  Writeln('  [upstreams]');
  Writeln('  dns1=1.1.1.1');
  Writeln('  dns2=8.8.8.8');
  Writeln('  dns3=[2606:4700:4700::1111]:53');
end;

function ParsePort(const S: AnsiString; out P: Word): Boolean;
var
  N: Integer;
begin
  Result := TryStrToInt(S, N) and (N >= 1) and (N <= 65535);
  if Result then
    P := N;
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
begin
  if not ParseUpstreamSpec(Spec, U) then
  begin
    Writeln(StdErr, 'Invalid upstream: ', Spec);
    Halt(1);
  end;
  SetLength(Upstreams, Length(Upstreams) + 1);
  Upstreams[High(Upstreams)] := U;
end;

procedure SetListenAll;
begin
  Bind4 := ANY_BIND4;
  Bind6 := ANY_BIND6;
end;

function ApplyOption(const Arg: AnsiString): Boolean;
begin
  Result := True;
  if Arg = '--listen-all' then
    SetListenAll
  else if Copy(Arg, 1, 8) = '--bind4=' then
    Bind4 := Copy(Arg, 9, MaxInt)
  else if Copy(Arg, 1, 8) = '--bind6=' then
    Bind6 := Copy(Arg, 9, MaxInt)
  else
    Result := False;
end;

procedure LoadConfig(const FileName: AnsiString);
var
  Ini: TIniFile;
  Values: TStringList;
  I: Integer;
  S, ListenMode: String;
begin
  if not FileExists(FileName) then
  begin
    Writeln(StdErr, 'Config file not found: ', FileName);
    Halt(1);
  end;

  Ini := TIniFile.Create(FileName);
  Values := TStringList.Create;
  try
    ListenPort := Ini.ReadInteger('server', 'port', 53);

    ListenMode := LowerCase(Trim(Ini.ReadString('server', 'listen_mode', 'local')));
    if ListenMode = 'all' then
      SetListenAll
    else
    begin
      Bind4 := DEFAULT_BIND4;
      Bind6 := DEFAULT_BIND6;
    end;

    S := Trim(Ini.ReadString('server', 'bind_ipv4', ''));
    if S <> '' then
      Bind4 := S;
    S := Trim(Ini.ReadString('server', 'bind_ipv6', ''));
    if S <> '' then
      Bind6 := S;

    Ini.ReadSectionValues('upstreams', Values);
    for I := 0 to Values.Count - 1 do
    begin
      S := Trim(Values.ValueFromIndex[I]);
      if S <> '' then
        AddUpstream(S);
    end;
  finally
    Values.Free;
    Ini.Free;
  end;
end;

function BindIPv4(const IP: AnsiString; Port: Word): LongInt;
var
  Addr: TInetSockAddr;
  Opt: LongInt;
  E: LongInt;
begin
  Result := fpsocket(AF_INET, SOCK_DGRAM, 0);
  if Result < 0 then
  begin
    E := fpgeterrno;
    Writeln(StdErr, 'IPv4 socket() failed: ', E, ' ', SysErrorMessage(E));
    Exit(-1);
  end;

  Opt := 1;
  fpsetsockopt(Result, SOL_SOCKET, SO_REUSEADDR, @Opt, SizeOf(Opt));

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(Port);
  Addr.sin_addr := StrToNetAddr(IP);

  if fpbind(Result, @Addr, SizeOf(Addr)) <> 0 then
  begin
    E := fpgeterrno;
    Writeln(StdErr, 'IPv4 bind(', IP, ':', Port, ') failed: ', E, ' ', SysErrorMessage(E));
    FpClose(Result);
    Exit(-1);
  end;
end;

function BindIPv6(const IP: AnsiString; Port: Word): LongInt;
var
  Addr: TInetSockAddr6;
  Opt: LongInt;
  E: LongInt;
begin
  Result := fpsocket(AF_INET6, SOCK_DGRAM, 0);
  if Result < 0 then
  begin
    E := fpgeterrno;
    Writeln(StdErr, 'IPv6 socket() failed: ', E, ' ', SysErrorMessage(E));
    Exit(-1);
  end;

  Opt := 1;
  fpsetsockopt(Result, SOL_SOCKET, SO_REUSEADDR, @Opt, SizeOf(Opt));
{$ifdef IPV6_V6ONLY}
  fpsetsockopt(Result, IPPROTO_IPV6, IPV6_V6ONLY, @Opt, SizeOf(Opt));
{$endif}

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin6_family := AF_INET6;
  Addr.sin6_port := htons(Port);
  Addr.sin6_addr := StrToHostAddr6(IP);

  if fpbind(Result, @Addr, SizeOf(Addr)) <> 0 then
  begin
    E := fpgeterrno;
    Writeln(StdErr, 'IPv6 bind([', IP, ']:', Port, ') failed: ', E, ' ', SysErrorMessage(E));
    FpClose(Result);
    Exit(-1);
  end;
end;

function ForwardQuery(const Packet: array of Byte; PacketLen: Integer; out Reply: TBytes): Integer;
var
  I, S, R: Integer;
  AddrLen: TSockLen;
  FromBuf: TSockAddrBuf;
  TV: TTimeVal;
begin
  Result := -1;
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

procedure SendSimpleError(Sock: LongInt; const PeerBuf: TSockAddrBuf; PeerLen: TSockLen;
  const Query: array of Byte; QueryLen: Integer; RCode: Byte);
var
  ID, Flags: Word;
  Q: TDNSQuestion;
  Resp: TBytes;
  IPv6: TIPv6Bytes;
  RespLen: Integer;
begin
  FillChar(IPv6, SizeOf(IPv6), 0);
  if ParseDNSQuestion(Query[0], QueryLen, ID, Flags, Q) then
  begin
    RespLen := BuildLocalResponse(Query[0], QueryLen, Q, RCode, IPv6, False, Resp);
    fpsendto(Sock, @Resp[0], RespLen, 0, @PeerBuf[0], PeerLen);
  end;
end;

procedure HandleOne(Sock: LongInt);
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
begin
  PeerLen := SizeOf(PeerBuf);
  N := fprecvfrom(Sock, @Buf[0], SizeOf(Buf), 0, @PeerBuf[0], @PeerLen);
  if N <= 0 then
    Exit;

  if not ParseDNSQuestion(Buf[0], N, ID, Flags, Q) then
  begin
    SendSimpleError(Sock, PeerBuf, PeerLen, Buf, N, DNS_RCODE_SERVFAIL);
    Exit;
  end;

  if (Q.QClass = DNS_CLASS_IN) and IsV6AltName(Q.QName) then
  begin
    if TryDecodeV6AltHost(Q.QName, IPv6) then
    begin
      if Q.QType = DNS_TYPE_AAAA then
        RespLen := BuildLocalResponse(Buf[0], N, Q, DNS_RCODE_NOERROR, IPv6, True, Resp)
      else
        RespLen := BuildLocalResponse(Buf[0], N, Q, DNS_RCODE_NOERROR, IPv6, False, Resp);
      fpsendto(Sock, @Resp[0], RespLen, 0, @PeerBuf[0], PeerLen);
      Exit;
    end
    else
    begin
      FillChar(IPv6, SizeOf(IPv6), 0);
      RespLen := BuildLocalResponse(Buf[0], N, Q, DNS_RCODE_NXDOMAIN, IPv6, False, Resp);
      fpsendto(Sock, @Resp[0], RespLen, 0, @PeerBuf[0], PeerLen);
      Exit;
    end;
  end;

  if Length(Upstreams) > 0 then
  begin
    RespLen := ForwardQuery(Buf, N, Forwarded);
    if RespLen > 0 then
    begin
      fpsendto(Sock, @Forwarded[0], RespLen, 0, @PeerBuf[0], PeerLen);
      Exit;
    end;
  end;

  SendSimpleError(Sock, PeerBuf, PeerLen, Buf, N, DNS_RCODE_SERVFAIL);
end;

procedure MainLoop;
var
  Readfds: TFDSet;
  MaxFD, R: LongInt;
begin
  while True do
  begin
    fpFD_ZERO(Readfds);
    MaxFD := -1;

    if Sock4 >= 0 then
    begin
      fpFD_SET(Sock4, Readfds);
      if Sock4 > MaxFD then
        MaxFD := Sock4;
    end;
    if Sock6 >= 0 then
    begin
      fpFD_SET(Sock6, Readfds);
      if Sock6 > MaxFD then
        MaxFD := Sock6;
    end;

    R := fpselect(MaxFD + 1, @Readfds, nil, nil, nil);
    if R <= 0 then
      Continue;

    if (Sock4 >= 0) and (fpFD_ISSET(Sock4, Readfds) <> 0) then
      HandleOne(Sock4);
    if (Sock6 >= 0) and (fpFD_ISSET(Sock6, Readfds) <> 0) then
      HandleOne(Sock6);
  end;
end;

var
  I, ArgIndex: Integer;
  TmpPort: Word;
  ConfigFile: AnsiString;
  Arg: AnsiString;
begin
  SetLength(Upstreams, 0);
  Bind4 := DEFAULT_BIND4;
  Bind6 := DEFAULT_BIND6;

  if ParamCount = 0 then
  begin
    Usage;
    Halt(1);
  end;

  if (ParamStr(1) = '-h') or (ParamStr(1) = '--help') then
  begin
    if ParamCount <> 1 then
    begin
      Writeln(StdErr, 'Error: -h/--help does not take additional arguments.');
      Halt(1);
    end;
    Usage;
    Halt(0);
  end;

  if ParamStr(1) = '-c' then
  begin
    ArgIndex := 2;
    ConfigFile := DEFAULT_CONFIG_FILE;
    if (ArgIndex <= ParamCount) and (Copy(ParamStr(ArgIndex), 1, 2) <> '--') then
    begin
      ConfigFile := ParamStr(ArgIndex);
      Inc(ArgIndex);
    end;

    LoadConfig(ConfigFile);

    while ArgIndex <= ParamCount do
    begin
      Arg := ParamStr(ArgIndex);
      if not ApplyOption(Arg) then
      begin
        Writeln(StdErr, 'Unknown option in config mode: ', Arg);
        Writeln(StdErr, 'Only bind/listen options are allowed after -c.');
        Halt(1);
      end;
      Inc(ArgIndex);
    end;
  end
  else
  begin
    if not ParsePort(ParamStr(1), TmpPort) then
    begin
      Writeln(StdErr, 'First argument must be a port number, or use -c.');
      Writeln(StdErr, '');
      Usage;
      Halt(1);
    end;

    ListenPort := TmpPort;

    if ParamCount < 2 then
    begin
      Writeln(StdErr, 'Error: command-line mode requires at least one upstream server.');
      Writeln(StdErr, '');
      Usage;
      Halt(1);
    end;

    for I := 2 to ParamCount do
    begin
      Arg := ParamStr(I);
      if not ApplyOption(Arg) then
        AddUpstream(Arg);
    end;
  end;

  Sock4 := BindIPv4(Bind4, ListenPort);
  Sock6 := BindIPv6(Bind6, ListenPort);

  if (Sock4 < 0) and (Sock6 < 0) then
  begin
    Writeln(StdErr, 'Could not bind either ', Bind4, ' or ', Bind6, ' on UDP port ', ListenPort);
    Halt(1);
  end;

  if Sock4 >= 0 then
    Writeln('Listening on ', Bind4, ':', ListenPort);
  if Sock6 >= 0 then
    Writeln('Listening on [', Bind6, ']:', ListenPort);

  if Length(Upstreams) > 0 then
  begin
    Writeln('Forwarding non-.v6.alt queries to:');
    for I := 0 to High(Upstreams) do
      if Upstreams[I].Kind = skIPv6 then
        Writeln('  [', Upstreams[I].Host, ']:', Upstreams[I].Port)
      else
        Writeln('  ', Upstreams[I].Host, ':', Upstreams[I].Port);
  end
  else
    Writeln('No upstreams configured; non-.v6.alt queries will get SERVFAIL.');

  MainLoop;
end.
