unit v6alt_codec;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  IPV6_LEN = 16;

type
  TIPv6Bytes = array[0..IPV6_LEN - 1] of Byte;

function TryDecodeV6AltHost(const Qname: AnsiString; out IPv6: TIPv6Bytes): Boolean;
function IPv6BytesToText(const IPv6: TIPv6Bytes): AnsiString;

implementation

uses
  v6alt_base32;

function EndsTextInsensitive(const Suffix, S: AnsiString): Boolean;
var
  LSuf, LStr: AnsiString;
begin
  LSuf := LowerCase(Suffix);
  LStr := LowerCase(S);
  Result := (Length(LStr) >= Length(LSuf)) and
            (Copy(LStr, Length(LStr) - Length(LSuf) + 1, Length(LSuf)) = LSuf);
end;

function RightMostEncodedLabel(const Host: AnsiString): AnsiString;
var
  Base, P: SizeInt;
begin
  Result := '';
  if not EndsTextInsensitive('.v6.alt', Host) then
    Exit;

  Base := Length(Host) - Length('.v6.alt') + 1;
  Result := Copy(Host, 1, Base - 1);
  if (Result <> '') and (Result[Length(Result)] = '.') then
    Delete(Result, Length(Result), 1);

  P := LastDelimiter('.', Result);
  if P > 0 then
    Result := Copy(Result, P + 1, MaxInt);
end;

function ExpandHyphenLabel(const Encoded: AnsiString; out Expanded: AnsiString): Boolean;
var
  I, HyphenCount: Integer;
  NeedA: Integer;
begin
  Result := False;
  Expanded := LowerCase(Encoded);
  HyphenCount := 0;

  for I := 1 to Length(Expanded) do
  begin
    if Expanded[I] = '-' then
      Inc(HyphenCount)
    else if not (Expanded[I] in ['a'..'z', '2'..'7']) then
      Exit;
  end;

  if HyphenCount > 1 then
    Exit;

  if HyphenCount = 1 then
  begin
    NeedA := 26 - Length(Expanded) + 1;
    if NeedA < 2 then
      Exit;
    Expanded := StringReplace(Expanded, '-', StringOfChar('a', NeedA), []);
  end;

  if Length(Expanded) <> 26 then
    Exit;

  Result := True;
end;

function TryDecodeV6AltHost(const Qname: AnsiString; out IPv6: TIPv6Bytes): Boolean;
var
  Encoded, Expanded, Uppered: AnsiString;
  Raw: TBytes;
  I: Integer;
begin
  Result := False;
  FillChar(IPv6, SizeOf(IPv6), 0);

  Encoded := RightMostEncodedLabel(Qname);
  if Encoded = '' then
    Exit;

  if not ExpandHyphenLabel(Encoded, Expanded) then
    Exit;

  Uppered := UpperCase(Expanded);
  if not DecodeBase32NoPadding(Uppered, Raw) then
    Exit;

  if Length(Raw) <> IPV6_LEN then
    Exit;

  for I := 0 to IPV6_LEN - 1 do
    IPv6[I] := Raw[I];

  Result := True;
end;

function IPv6BytesToText(const IPv6: TIPv6Bytes): AnsiString;
var
  W: array[0..7] of Word;
  I, BestStart, BestLen, CurStart, CurLen: Integer;
  First: Boolean;
  Part: AnsiString;
begin
  for I := 0 to 7 do
    W[I] := (Word(IPv6[I * 2]) shl 8) or Word(IPv6[I * 2 + 1]);

  BestStart := -1;
  BestLen := 0;
  CurStart := -1;
  CurLen := 0;
  for I := 0 to 7 do
  begin
    if W[I] = 0 then
    begin
      if CurStart < 0 then
      begin
        CurStart := I;
        CurLen := 1;
      end
      else
        Inc(CurLen);
    end
    else
    begin
      if CurLen > BestLen then
      begin
        BestStart := CurStart;
        BestLen := CurLen;
      end;
      CurStart := -1;
      CurLen := 0;
    end;
  end;
  if CurLen > BestLen then
  begin
    BestStart := CurStart;
    BestLen := CurLen;
  end;
  if BestLen < 2 then
  begin
    BestStart := -1;
    BestLen := 0;
  end;

  Result := '';
  First := True;
  I := 0;
  while I <= 7 do
  begin
    if (BestLen > 0) and (I = BestStart) then
    begin
      if First then
        Result := '::'
      else
        Result := Result + ':';
      Inc(I, BestLen);
      First := False;
      if I > 7 then
        Break;
      Continue;
    end;

    if not First then
      Result := Result + ':';
    Part := IntToHex(W[I], 1);
    while (Length(Part) > 1) and (Part[1] = '0') do
      Delete(Part, 1, 1);
    Result := Result + LowerCase(Part);
    First := False;
    Inc(I);
  end;

  if Result = '' then
    Result := '::';
end;

end.
