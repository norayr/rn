unit dns_packet;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, v6alt_codec;

const
  DNS_TYPE_A     = 1;
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
function BuildLocalResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  RCode: Byte; const IPv6: TIPv6Bytes; HasAnswer: Boolean; out Resp: TBytes): Integer;
function IsV6AltName(const QName: AnsiString): Boolean;

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

function BuildLocalResponse(const Query; QueryLen: Integer; const Q: TDNSQuestion;
  RCode: Byte; const IPv6: TIPv6Bytes; HasAnswer: Boolean; out Resp: TBytes): Integer;
var
  QLen, Posn: Integer;
  QueryFlags, RespFlags: Word;
  AnCount: Word;
  I: Integer;
begin
  QLen := Q.EndOffset - 12;
  if QLen < 0 then
    QLen := 0;

  AnCount := 0;
  if HasAnswer then
    AnCount := 1;

  if HasAnswer then
    SetLength(Resp, 12 + QLen + 28)
  else
    SetLength(Resp, 12 + QLen);

  Move(Query, Resp[0], 12 + QLen);

  QueryFlags := ReadBE16(Query, 2);
  RespFlags := $8000 or (QueryFlags and $0100) or Word(RCode);
  if HasAnswer then
    RespFlags := RespFlags or $0400;

  WriteBE16(Resp, 0, ReadBE16(Query, 0));
  WriteBE16(Resp, 2, RespFlags);
  WriteBE16(Resp, 4, 1);
  WriteBE16(Resp, 6, AnCount);
  WriteBE16(Resp, 8, 0);
  WriteBE16(Resp, 10, 0);

  Posn := 12 + QLen;
  if HasAnswer then
  begin
    WriteBE16(Resp, Posn + 0, $C00C);
    WriteBE16(Resp, Posn + 2, DNS_TYPE_AAAA);
    WriteBE16(Resp, Posn + 4, DNS_CLASS_IN);
    WriteBE32(Resp, Posn + 6, 60);
    WriteBE16(Resp, Posn + 10, 16);
    for I := 0 to 15 do
      Resp[Posn + 12 + I] := IPv6[I];
    Inc(Posn, 28);
  end;

  Result := Posn;
end;

end.
