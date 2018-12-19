unit LogProvider;

interface

uses
  Windows, Classes, SysUtils, DB, LogTypes, Contnrs, Forms, SqlExpr;

type
  TLogDBConnection = class(TPersistent)
  private
    FUserName: string;
    FPassword: string;
    FDataBase: string;
    FSQLConnection: TSQLConnection;
    function ArquivoConfiguracao: string;
    procedure ConnectToDataBase;
    function SavePointToString(ASavePoint: TObjectList): string;
  protected
    procedure SaveLog(ATableName, AUserName: string; AOperation: TLogOperation; ASavePoint: TObjectList);
  public
    constructor Create;
    destructor Destroy; override;

    property DataBase: string read FDataBase write FDataBase;
    property UserName: string read FUserName write FUserName;
    property Password: string read FPassword write FPassword;
  end;

  TLogAdditionalValues = procedure (ATableName: string; var AValues: TArrayLogData; var UserName: string) of object;

  TLogProviderList = class(TComponent)
  private
    FList: TObjectList;
    FDBConnection: TLogDBConnection;
    FOnAdditionalValues: TLogAdditionalValues;
    function GetCount: Integer;
  protected
    procedure SaveLog(ATableName: string; AOperation: TLogOperation; ASavePoint: TObjectList);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure AddProvider(ADataSet: TDataSet; ATableName: string; AImportantFieldNames: array of string);

    property Count: Integer read GetCount;
    property DBConnection: TLogDBConnection read FDBConnection;
    property OnAdditionalValues: TLogAdditionalValues read FOnAdditionalValues write FOnAdditionalValues;
  end;

function LogProviderList: TLogProviderList;

implementation

uses
  DateUtils, IniFiles, IdCoderMIME;

const
  cArquivoConfiguracao = 'Config.ini';

type
  TLogProvider = class(TComponent)
  private
    FSaveAfterDelete: TDataSetNotifyEvent;
    FSaveBeforeCancel: TDataSetNotifyEvent;
    FSaveBeforeEdit: TDataSetNotifyEvent;
    FsaveBeforeDelete: TDataSetNotifyEvent;
    FSaveBeforePost: TDataSetNotifyEvent;

    FDataSet: TDataSet;
    FImportantFieldNames: array of string;
    FOperation: TLogOperation;
    FSavePoint: TObjectList;
    FTableName: string;
    FProviderList: TLogProviderList;
    procedure AddInternalEvents;
    procedure RemoveInternalEvents;
    procedure SetDataSet(const Value: TDataSet);
  protected
    procedure ClearSavePoint;
    procedure CreateSavePoint;
    procedure CommitSavePoint;

    procedure DoInternalAfterDelete(DataSet: TDataSet); virtual;
    procedure DoInternalBeforeCancel(DataSet: TDataSet); virtual;
    procedure DoInternalBeforeEdit(DataSet: TDataSet); virtual;
    procedure DoInternalBeforeDelete(DataSet: TDataSet); virtual;
    procedure DoInternalBeforePost(DataSet: TDataSet); virtual;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AProviderList: TLogProviderList; ADataSet: TDataSet; ATableName: string; AImportantFieldNames: array of string); reintroduce;
    destructor Destroy; override;
    property DataSet: TDataSet read FDataSet write SetDataSet;
    property TableName: string read FTableName write FTableName;
  end;

var
  _LogProviderList: TLogProviderList = nil;

function LogProviderList: TLogProviderList;
begin
  if not Assigned(_LogProviderList) then
    _LogProviderList := TLogProviderList.Create(nil);

  Result := _LogProviderList;
end;

{ TLogProvider }

procedure TLogProvider.AddInternalEvents;
begin
  FSaveAfterDelete  := DataSet.AfterDelete;
  FSaveBeforeCancel := FDataSet.BeforeCancel;
  FSaveBeforeEdit   := FDataSet.BeforeEdit;
  FsaveBeforeDelete := FDataSet.BeforeDelete;
  FSaveBeforePost   := FDataSet.BeforePost;

  FDataSet.AfterDelete  := DoInternalAfterDelete;
  FDataSet.BeforeCancel := DoInternalBeforeCancel;
  FDataSet.BeforeEdit   := DoInternalBeforeEdit;
  FDataSet.BeforeDelete := DoInternalBeforeDelete;
  FDataSet.BeforePost   := DoInternalBeforePost;
end;

procedure TLogProvider.ClearSavePoint;
begin
  FSavePoint.Clear;
end;

procedure TLogProvider.CommitSavePoint;
var
  LogData: TLogData;
  I, iTotal: Integer;
begin
  iTotal := 0;
  for I := FSavePoint.Count - 1 downto 0 do
  begin
    LogData := (FSavePoint[I] as TLogData);
    if LogData.AdditionalValue then
      Continue;

    if ( SameText(LogData.Value, FDataSet.FieldByName(LogData.Name).AsString) ) and
       (FOperation = loEdit) then
    begin
      FSavePoint.Delete(I);
    end
    else
    begin
      case FOperation of
        loInsert:
          begin
            LogData.Value    := EmptyStr;
            LogData.NewValue := FDataSet.FieldByName(LogData.Name).AsString;
          end;
        loEdit:
          begin
            LogData.NewValue := FDataSet.FieldByName(LogData.Name).AsString;
          end;
        loDelete:
          begin
            LogData.NewValue := EmptyStr;
          end;
      end;
      Inc(iTotal);
    end;
  end;

  if (iTotal > 0) then
    FProviderList.SaveLog(FTableName, FOperation, FSavePoint);

  ClearSavePoint;
end;

constructor TLogProvider.Create(AProviderList: TLogProviderList;
  ADataSet: TDataSet; ATableName: string; AImportantFieldNames: array of string);
var
  I: Integer;
begin
  inherited Create(nil);
  FSavePoint    := TObjectList.Create(True);
  FProviderList := AProviderList;
  DataSet       := ADataSet;
  TableName     := ATableName;

  SetLength(FImportantFieldNames, Length(AImportantFieldNames));
  for I := Low(AImportantFieldNames) to High(AImportantFieldNames) do
    if AImportantFieldNames[I] <> '' then
      FImportantFieldNames[I] := AImportantFieldNames[I];
end;

procedure TLogProvider.CreateSavePoint;

  procedure AddLogField(AField: TField; AAditionalValue: Boolean);
  begin
    if Assigned(AField) and (AField.FieldKind = fkData) and (AField.DataType <> ftBlob) then
      FSavePoint.Add( TLogData.Create( AField.FieldName,
                                       AField.AsString,
                                       AAditionalValue) );
  end;

var
  I: Integer;
  Field: TField;
begin
  ClearSavePoint;

  for I := 0 to FDataSet.FieldCount - 1 do
  begin
    Field := FDataSet.Fields[I];
    AddLogField( Field, False );
//    if (Field.FieldKind = fkData) and (Field.DataType <> ftBlob) then
//    begin
//      FSavePoint.Add( TLogData.Create(Field.FieldName,
//                      Field.AsString,
//                      False ) );
//    end;
  end;

  for I := Low(FImportantFieldNames) to High(FImportantFieldNames) do
  begin
    Field := FDataSet.FindField(FImportantFieldNames[I]);
    AddLogField( Field, True );
//    begin
//      FSavePoint.Add( TLogData.Create(Field.FieldName,
//                      Field.AsString,
//                      True ) );
//    end;
  end;
end;

destructor TLogProvider.Destroy;
begin
  FreeAndNil(FSavePoint);
  inherited;
end;

procedure TLogProvider.DoInternalAfterDelete(DataSet: TDataSet);
begin
  if Assigned(FSaveAfterDelete) then
    FSaveAfterDelete(DataSet);
  CommitSavePoint;
end;

procedure TLogProvider.DoInternalBeforeCancel(DataSet: TDataSet);
begin
  if Assigned(FSaveBeforeCancel) then
    FSaveBeforeCancel(DataSet);
  ClearSavePoint;
end;

procedure TLogProvider.DoInternalBeforeDelete(DataSet: TDataSet);
begin
  if Assigned(FSaveBeforeDelete) then
    FsaveBeforeDelete(DataSet);

  FOperation := loDelete;
  CreateSavePoint;
end;

procedure TLogProvider.DoInternalBeforeEdit(DataSet: TDataSet);
begin
  if Assigned(FSaveBeforeEdit) then
    FSaveBeforeEdit(DataSet);

  FOperation := loEdit;
  CreateSavePoint;
end;

procedure TLogProvider.DoInternalBeforePost(DataSet: TDataSet);
begin
  if Assigned(FSaveBeforePost) then
    FSaveBeforePost(DataSet);

  if (DataSet.State = dsInsert) then
  begin
    FOperation := loInsert;
    CreateSavePoint;
  end;

  CommitSavePoint;
end;

procedure TLogProvider.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (AComponent = FDataSet) and (Operation = opRemove) then
    FDataSet := nil;
end;

procedure TLogProvider.RemoveInternalEvents;
begin
  FDataSet.AfterDelete  := FSaveAfterDelete;
  FDataSet.BeforeCancel := FSaveBeforeCancel;
  FDataSet.BeforeEdit   := FSaveBeforeEdit;
  FDataSet.BeforeDelete := FsaveBeforeDelete;
  FDataSet.BeforePost   := FSaveBeforePost;
end;

procedure TLogProvider.SetDataSet(const Value: TDataSet);
begin
  if (FDataSet <> Value) then
  begin
    if Assigned(FDataSet) then
    begin
      RemoveInternalEvents;
      FDataSet.RemoveFreeNotification(Self);
    end;

    FDataSet := Value;
    FDataSet.FreeNotification(Self);
    AddInternalEvents;
  end;
end;

{ TLogProviderList }

procedure TLogProviderList.AddProvider(ADataSet: TDataSet; ATableName: string;
  AImportantFieldNames: array of string);
begin
  FList.Add( TLogProvider.Create(Self, ADataSet, ATableName, AImportantFieldNames) );
end;

constructor TLogProviderList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FList         := TObjectList.Create(True);
  FDBConnection := TLogDBConnection.Create;
end;

destructor TLogProviderList.Destroy;
begin
  FreeAndNil(FDBConnection);
  FreeAndNil(FList);
  inherited;
end;

function TLogProviderList.GetCount: Integer;
begin
  Result := FList.Count;
end;

procedure TLogProviderList.SaveLog(ATableName: string; AOperation: TLogOperation;
  ASavePoint: TObjectList);
var
  Values: TArrayLogData;
  I: Integer;
  StrUserName: string;
begin
  SetLength(Values, 0);
  if Assigned(FOnAdditionalValues) then
    FOnAdditionalValues(ATableName, Values, StrUserName);

  for I := Low(Values) to High(Values) do
  begin
    ASavePoint.Add( TLogData.Create( Values[I].Name,
                                     Values[I].Value,
                                     True ) );
  end;

  FDBConnection.SaveLog(ATableName, StrUserName, AOperation, ASavePoint);
end;

{ TLogDBConnection }

function TLogDBConnection.ArquivoConfiguracao: string;
begin
  Result := ExtractFilePath( Application.ExeName ) + cArquivoConfiguracao;
end;

procedure TLogDBConnection.ConnectToDataBase;
begin
  FSQLConnection.Params.Values['Database']  := FDataBase;
  FSQLConnection.Params.Values['User_Name'] := FUserName;
  FSQLConnection.Params.Values['Password']  := FPassword;
  FSQLConnection.Connected                  := True;
end;

constructor TLogDBConnection.Create;
var
  Config: TIniFile;
  Decoder64: TIdDecoderMIME;
begin
  inherited Create;

  FSQLConnection := TSQLConnection.Create(nil);
  FSQLConnection.Name           := '_SQLConection';
  FSQLConnection.ConnectionName := 'IBConnection';
  FSQLConnection.DriverName     := 'Interbase';
  FSQLConnection.GetDriverFunc  := 'getSQLDriverINTERBASE';
  FSQLConnection.LibraryName    := 'dbexpint.dll';
  FSQLConnection.LoginPrompt    := False;
  FSQLConnection.Params.Clear;
  FSQLConnection.Params.Add('DriverName=Interbase');
  FSQLConnection.Params.Add('Database=');
  FSQLConnection.Params.Add('RoleName=RoleName');
  FSQLConnection.Params.Add('User_Name=');
  FSQLConnection.Params.Add('Password=');
  FSQLConnection.Params.Add('ServerCharSet=');
  FSQLConnection.Params.Add('SQLDialect=3');
  FSQLConnection.Params.Add('ErrorResourceFile=');
  FSQLConnection.Params.Add('LocaleCode=0000');
  FSQLConnection.Params.Add('BlobSize=-1');
  FSQLConnection.Params.Add('CommitRetain=False');
  FSQLConnection.Params.Add('WaitOnLocks=True');
  FSQLConnection.Params.Add('Interbase TransIsolation=ReadCommited');
  FSQLConnection.Params.Add('Trim Char=False');
  FSQLConnection.VendorLib := 'gds32.dll';

  if not FileExists(ArquivoConfiguracao) then
    Exit;

  Config    := TIniFile.Create( ArquivoConfiguracao );
  Decoder64 := TIdDecoderMIME.Create(nil);
  try
    FDataBase  := Config.ReadString('bando de dados', 'database', '');
    FUserName  := Config.ReadString('bando de dados', 'username', '');
    FPassword  := Decoder64.DecodeString( Config.ReadString('bando de dados', 'password', '') );
  finally
    FreeAndNil(Decoder64);
    FreeAndNil(Config);
  end;
end;

destructor TLogDBConnection.Destroy;
begin
  FreeAndNil(FSQLConnection);
  inherited;
end;

procedure TLogDBConnection.SaveLog(ATableName, AUserName: string;
  AOperation: TLogOperation; ASavePoint: TObjectList);
var
  SQL: TSQLDataSet;
begin
  if not FSQLConnection.Connected then
    ConnectToDataBase;

  SQL := TSQLDataSet.Create(nil);
  try
    SQL.SQLConnection := FSQLConnection;
    SQL.NoMetadata := True;
    SQL.CommandText   := 'insert into log_sistema ' + sLineBreak +
                         '  (id_log, nome_tabela, operacao, usuario, data_operacao, hora_operacao, log) ' + sLineBreak +
                         ' values ' + sLineBreak +
                         '   (gen_id(log_id, 1), :nome_tabela, :operacao, :usuario, :data_operacao, :hora_operacao, :log)';
    if SQL.ParamCheck then
    begin
      SQL.ParamByName('nome_tabela').AsString := ATableName;
      SQL.ParamByName('operacao').AsInteger   := Ord(AOperation);
      SQL.ParamByName('usuario').AsString     := AUserName;
      SQL.ParamByName('data_operacao').AsDate := DateOf(Now);
      SQL.ParamByName('hora_operacao').AsTime := TimeOf(Now);
      SQL.ParamByName('log').AsBlob           := SavePointToString(ASavePoint);

      SQL.ExecSQL;
    end;
  finally
    FreeAndNil(SQL);
  end;
end;

function TLogDBConnection.SavePointToString(ASavePoint: TObjectList): string;
var
  I: Integer;
  LogData: TLogData;
  OldValue, NewValue, AddValue: string;
begin
  Result := EmptyStr;

  OldValue := EmptyStr;
  NewValue := EmptyStr;
  AddValue := EmptyStr;
  for I := 0 to ASavePoint.Count - 1 do
  begin
    LogData  := (ASavePoint[I] as TLogData);

    if LogData.AdditionalValue then
    begin
      if not SameText(Trim(LogData.Value), EmptyStr) then
        AddValue := AddValue +
                    Format('%s: %s', [ LogData.Name, LogData.Value ]) +
                    sLineBreak;
    end
    else
    begin
      if not SameText(Trim(LogData.Value), EmptyStr) then
        OldValue := OldValue +
                    Format('%s: %s', [ LogData.Name, LogData.Value ]) +
                    sLineBreak;
      if not SameText(Trim(LogData.NewValue), EmptyStr) then
        NewValue := NewValue +
                    Format('%s: %s', [ LogData.Name, LogData.NewValue ]) +
                    sLineBreak;
    end;
  end;

  Result := '[ Valores anteriores ]' + sLineBreak + Trim(OldValue) + sLineBreak +
    sLineBreak + '[ Novos valores ]' + sLineBreak + Trim(NewValue) + sLineBreak +
    sLineBreak + '[ Valores Adicionais ]' + sLineBreak + Trim(AddValue);
end;

initialization
finalization
  if Assigned(_LogProviderList) then
    FreeAndNil(_LogProviderList);

end.
