program v6alt;

{$mode objfpc}{$H+}

uses
  SysUtils, Sockets, v6alt_codec;

procedure Usage;
begin
  Writeln('v6alt - convert between IPv6 addresses and .v6.alt names');
  Writeln('');
  Writeln('Usage:');
  Writeln('  v6alt <ipv6-or-v6.alt-name>');
  Writeln('  v6alt -h | --help');
  Writeln('');
  Writeln('Examples:');
  Writeln('  v6alt 2001:db8::1');
  Writeln('  v6alt eaaq3o-e.v6.alt');
  Writeln('');
  Writeln('The program detects the input automatically:');
  Writeln('  IPv6 input    -> prints the corresponding .v6.alt name');
  Writeln('  .v6.alt input -> prints the corresponding IPv6 address');
end;

function EndsWithInsensitive(const S, Suffix: AnsiString): Boolean;
begin
  Result := (Length(S) >= Length(Suffix)) and
            (LowerCase(Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix))) =
             LowerCase(Suffix));
end;

function TryParseIPv6Text(const S: AnsiString; out IPv6: TIPv6Bytes): Boolean;
var
  A6: TInetSockAddr6;
  I: Integer;
begin
  Result := False;
  FillChar(IPv6, SizeOf(IPv6), 0);
  try
    FillChar(A6, SizeOf(A6), 0);
    A6.sin6_addr := StrToHostAddr6(S);
    for I := 0 to 15 do
      IPv6[I] := A6.sin6_addr.s6_addr[I];
    Result := True;
  except
    Result := False;
  end;
end;

procedure Fail(const Msg: AnsiString);
begin
  Writeln(StdErr, 'v6alt: ', Msg);
  Halt(1);
end;

var
  Input: AnsiString;
  IPv6: TIPv6Bytes;
begin
  if ParamCount < 1 then
  begin
    Usage;
    Halt(1);
  end;

  Input := Trim(ParamStr(1));

  if (Input = '-h') or (Input = '--help') then
  begin
    Usage;
    Halt(0);
  end;

  if ParamCount <> 1 then
    Fail('expected exactly one argument');

  if EndsWithInsensitive(Input, '.v6.alt') then
  begin
    if not TryDecodeV6AltHost(Input, IPv6) then
      Fail('invalid .v6.alt name: ' + Input);
    Writeln(IPv6BytesToText(IPv6));
    Halt(0);
  end;

  if TryParseIPv6Text(Input, IPv6) then
  begin
    Writeln(IPv6BytesToV6AltHost(IPv6));
    Halt(0);
  end;

  Fail('input is neither a valid IPv6 address nor a valid .v6.alt name');
end.
