unit dns_packet;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes(* for string list *), v6alt_codec;

const
  DNS_TYPE_A     = 1;
  DNS_TYPE_PTR   = 12;
  DNS_TYPE_AAAA  = 28;
  DNS_CLASS_IN   = 1;

  DNS_RCODE_NOERROR  = 0;
  DNS_RCODE_SERVFAIL = 2;
  DNS_RCODE_NXDOMAIN = 3;

type
  TDNSQuestion = record
    QName: AnsiString;
    QType: Word;
    QClass: Word;
    EndOffset: Integer;
  end;

function ParseDNSQuestion(const Buf; Len: Integer; out ID, Flags: Word;
  out Q: TDNSQuestion): Boolean;
function BuildNoDataResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  RCode: Byte; out Resp: TBytes): Integer;
function BuildAAAAResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  const IPv6: TIPv6Bytes; TTL: LongWord; out Resp: TBytes): Integer;
function BuildPTRResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  const PtrName: AnsiString; TTL: LongWord; out Resp: TBytes): Integer;
function IsV6AltName(const QName: AnsiString): Boolean;
function IsIP6ArpaName(const QName: AnsiString): Boolean;

implementation

function ReadBE16(const Buf; Offset: Integer): Word;
var
  P: PByte;
begin
  P := @Buf;
  Inc(P, Offset);
  Result := (Word(P^) shl 8);
  Inc(P);
  Result := Result or Word(P^);
end;

procedure WriteBE16(var Buf: TBytes; Offset: Integer; Value: Word);
begin
  Buf[Offset] := Byte((Value shr 8) and $FF);
  Buf[Offset + 1] := Byte(Value and $FF);
end;

procedure WriteBE32(var Buf: TBytes; Offset: Integer; Value: LongWord);
begin
  Buf[Offset] := Byte((Value shr 24) and $FF);
  Buf[Offset + 1] := Byte((Value shr 16) and $FF);
  Buf[Offset + 2] := Byte((Value shr 8) and $FF);
  Buf[Offset + 3] := Byte(Value and $FF);
end;

function IsV6AltName(const QName: AnsiString): Boolean;
var
  L: AnsiString;
begin
  L := LowerCase(QName);
  Result := (L = 'v6.alt') or ((Length(L) > Length('.v6.alt')) and
    (Copy(L, Length(L) - Length('.v6.alt') + 1, Length('.v6.alt')) = '.v6.alt'));
end;

function IsIP6ArpaName(const QName: AnsiString): Boolean;
var
  L: AnsiString;
begin
  L := LowerCase(QName);
  Result := (L = 'ip6.arpa') or ((Length(L) > Length('.ip6.arpa')) and
    (Copy(L, Length(L) - Length('.ip6.arpa') + 1, Length('.ip6.arpa')) = '.ip6.arpa'));
end;

function ParseQName(const Buf; Len, StartOffset: Integer; out Name: AnsiString;
  out EndOffset: Integer): Boolean;
var
  Posn, L, I: Integer;
  P: PByte;
  LabelStr: AnsiString;
begin
  Result := False;
  Name := '';
  Posn := StartOffset;
  P := @Buf;

  while Posn < Len do
  begin
    L := PByte(P + Posn)^;
    Inc(Posn);

    if L = 0 then
    begin
      EndOffset := Posn;
      Result := True;
      Exit;
    end;

    if (L and $C0) <> 0 then
      Exit;
    if Posn + L > Len then
      Exit;

    LabelStr := '';
    SetLength(LabelStr, L);
    for I := 1 to L do
      LabelStr[I] := Char(PByte(P + Posn + I - 1)^);

    if Name <> '' then
      Name := Name + '.';
    Name := Name + LabelStr;
    Inc(Posn, L);
  end;
end;

function ParseDNSQuestion(const Buf; Len: Integer; out ID, Flags: Word;
  out Q: TDNSQuestion): Boolean;
var
  QDCount: Word;
begin
  Result := False;
  FillChar(Q, SizeOf(Q), 0);
  if Len < 12 then
    Exit;

  ID := ReadBE16(Buf, 0);
  Flags := ReadBE16(Buf, 2);
  QDCount := ReadBE16(Buf, 4);
  if QDCount <> 1 then
    Exit;

  if not ParseQName(Buf, Len, 12, Q.QName, Q.EndOffset) then
    Exit;
  if Q.EndOffset + 4 > Len then
    Exit;

  Q.QType := ReadBE16(Buf, Q.EndOffset);
  Q.QClass := ReadBE16(Buf, Q.EndOffset + 2);
  Inc(Q.EndOffset, 4);
  Result := True;
end;

function EncodeQNameWire(const Name: AnsiString; out Wire: TBytes): Integer;
var
  Labels: TStringList;
  I, L, Posn: Integer;
  S: AnsiString;
begin
  Labels := TStringList.Create;
  try
    Labels.StrictDelimiter := True;
    Labels.Delimiter := '.';
    Labels.DelimitedText := Name;
    SetLength(Wire, Length(Name) + 2);
    Posn := 0;
    for I := 0 to Labels.Count - 1 do
    begin
      S := Labels[I];
      L := Length(S);
      Wire[Posn] := Byte(L);
      Inc(Posn);
      if L > 0 then
      begin
        Move(S[1], Wire[Posn], L);
        Inc(Posn, L);
      end;
    end;
    Wire[Posn] := 0;
    Inc(Posn);
    SetLength(Wire, Posn);
    Result := Posn;
  finally
    Labels.Free;
  end;
end;

function BuildBaseResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  RCode: Byte; AnswerCount: Word; ExtraLen: Integer; out Resp: TBytes): Integer;
var
  QLen: Integer;
  QueryFlags, RespFlags: Word;
begin
  QLen := Q.EndOffset - 12;
  if QLen < 0 then
    QLen := 0;

  SetLength(Resp, 12 + QLen + ExtraLen);
  Move(Query, Resp[0], 12 + QLen);

  QueryFlags := ReadBE16(Query, 2);
  RespFlags := $8000 or (QueryFlags and $0100) or Word(RCode);
  if AnswerCount > 0 then
    RespFlags := RespFlags or $0400;

  WriteBE16(Resp, 0, ReadBE16(Query, 0));
  WriteBE16(Resp, 2, RespFlags);
  WriteBE16(Resp, 4, 1);
  WriteBE16(Resp, 6, AnswerCount);
  WriteBE16(Resp, 8, 0);
  WriteBE16(Resp, 10, 0);

  Result := 12 + QLen;
end;

function BuildNoDataResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  RCode: Byte; out Resp: TBytes): Integer;
begin
  Result := BuildBaseResponse(Query, QueryLen, Q, RCode, 0, 0, Resp);
end;

function BuildAAAAResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  const IPv6: TIPv6Bytes; TTL: LongWord; out Resp: TBytes): Integer;
var
  Posn, I: Integer;
begin
  Posn := BuildBaseResponse(Query, QueryLen, Q, DNS_RCODE_NOERROR, 1, 28, Resp);
  WriteBE16(Resp, Posn + 0, $C00C);
  WriteBE16(Resp, Posn + 2, DNS_TYPE_AAAA);
  WriteBE16(Resp, Posn + 4, DNS_CLASS_IN);
  WriteBE32(Resp, Posn + 6, TTL);
  WriteBE16(Resp, Posn + 10, 16);
  for I := 0 to 15 do
    Resp[Posn + 12 + I] := IPv6[I];
  Result := Posn + 28;
end;

function BuildPTRResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  const PtrName: AnsiString; TTL: LongWord; out Resp: TBytes): Integer;
var
  Posn, NameLen: Integer;
  NameWire: TBytes;
begin
  NameLen := EncodeQNameWire(PtrName, NameWire);
  Posn := BuildBaseResponse(Query, QueryLen, Q, DNS_RCODE_NOERROR, 1, 12 + NameLen, Resp);
  WriteBE16(Resp, Posn + 0, $C00C);
  WriteBE16(Resp, Posn + 2, DNS_TYPE_PTR);
  WriteBE16(Resp, Posn + 4, DNS_CLASS_IN);
  WriteBE32(Resp, Posn + 6, TTL);
  WriteBE16(Resp, Posn + 10, NameLen);
  if NameLen > 0 then
    Move(NameWire[0], Resp[Posn + 12], NameLen);
  Result := Posn + 12 + NameLen;
end;

end.
