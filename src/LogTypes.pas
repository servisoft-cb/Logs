unit LogTypes;

interface

type
  TLogData = class
  private
    FAdditionalValue: Boolean;
    FValue: string;
    FName: string;
    FNewValue: string;
  public
    constructor Create(AName, AValue: string; AAdditionalValue: Boolean);
    property Name: string read FName write FName;
    property Value: string read FValue write FValue;
    property NewValue: string read FNewValue write FNewValue;
    property AdditionalValue: Boolean read FAdditionalValue write FAdditionalValue;
  end;

  TLogDataRec = record
    Name: string;
    Value: string;
  end;

  TArrayLogData = array of TLogDataRec;

  TLogOperation = (loInsert = 0, loEdit = 1, loDelete = 2);

implementation

uses SysUtils;

{ TLogData }

constructor TLogData.Create(AName, AValue: string;
  AAdditionalValue: Boolean);
begin
  inherited Create;
  FName     := AName;
  FValue    := AValue;
  FNewValue := EmptyStr;
  FAdditionalValue := AAdditionalValue; 
end;

end.
