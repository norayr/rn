unit v6alt_base32;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function DecodeBase32NoPadding(const S: AnsiString; out Raw: TBytes): Boolean;

implementation

function Base32Value(C: Char): Integer;
begin
  case UpCase(C) of
    'A'..'Z': Result := Ord(UpCase(C)) - Ord('A');
    '2'..'7': Result := 26 + (Ord(C) - Ord('2'));
  else
    Result := -1;
  end;
end;

function DecodeBase32NoPadding(const S: AnsiString; out Raw: TBytes): Boolean;
var
  I, V: Integer;
  Acc: QWord;
  Bits: Integer;
  OutLen: Integer;
  C: Char;
begin
  Result := False;
  SetLength(Raw, 0);
  Acc := 0;
  Bits := 0;
  OutLen := 0;

  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C = '=' then
      Continue;

    V := Base32Value(C);
    if V < 0 then
      Exit;

    Acc := (Acc shl 5) or QWord(V);
    Inc(Bits, 5);

    while Bits >= 8 do
    begin
      if OutLen >= Length(Raw) then
        SetLength(Raw, OutLen + 16);

      Raw[OutLen] := Byte((Acc shr (Bits - 8)) and $FF);
      Inc(OutLen);
      Dec(Bits, 8);

      { Keep only the remaining unconsumed bits. }
      if Bits = 0 then
        Acc := 0
      else
        Acc := Acc and ((QWord(1) shl Bits) - 1);
    end;
  end;

  SetLength(Raw, OutLen);
  Result := True;
end;


end.
