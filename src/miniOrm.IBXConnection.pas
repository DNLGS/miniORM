
unit miniOrm.IBXConnection;

interface

uses
  SysUtils,
  Variants,
  Generics.Collections,
  Generics.Defaults,
  miniOrm.DatabaseConnection.Intf,
  miniOrm.Types,
  IBX.IBSQL,
  IBX.IBDatabase,
  IBX.IBHeader,
  Data.FmtBcd;

type
  TIBXDatabaseConnection = class(
    TInterfacedObject,
    IDatabaseConnection)
  private
    FTransaction: TIBTransaction;
    FConnection: TIBDatabase;
    FIsolation: TTransactionIsolation;
    FVersion: Int64;
    FReadOnly: Boolean;

    procedure CheckTransaction;
    procedure BindParams(
      const ASQL: TIBSQL;
      const AParams: TParams);

  public
    constructor Create(const ADatabase: TIBDatabase);
    destructor Destroy; override;

    procedure BeginTransaction(AIsolation: TTransactionIsolation = tiSnapshot);
    procedure Commit;
    procedure Rollback;

    function OpenReadSession: IDatabaseConnection;
    function InTransaction: Boolean;
    function TransactionIsolation: TTransactionIsolation;
    function TransactionVersion: Int64;

    function Execute(
      const ASQL: string;
      const AParams: TParams): Int64;

    function Query(const ASQL: string; const AParams: TParams;
      AMaxRows: Integer = 0): TObjectList<TValues>;

    function ExecuteWithReturn(
      const ASQL: string;
      const AParams: TParams): TValues;
  end;

implementation

{ TIBXDatabaseConnection }

constructor TIBXDatabaseConnection.Create(
  const ADatabase: TIBDatabase);
begin
  inherited Create;

  if ADatabase = nil then
    raise EArgumentNilException.Create('A conexão não pode ser nil.');

  FConnection := ADatabase;

  FTransaction := TIBTransaction.Create(nil);
  try
    FTransaction.DefaultDatabase := FConnection;

  except
    FTransaction.Free;
    FTransaction := nil;
    raise;
  end;
end;

destructor TIBXDatabaseConnection.Destroy;
begin
  try
    if FTransaction <> nil then
    begin
      try
        if FTransaction.InTransaction then
          FTransaction.Rollback;
      finally
        FTransaction.Free;
      end;
    end;
  finally
    inherited Destroy;
  end;
end;

procedure TIBXDatabaseConnection.CheckTransaction;
begin
  if not FConnection.Connected then
    raise Exception.Create(
      'A conexão com o banco está fechada.');

  if not FTransaction.InTransaction then
    raise Exception.Create('Nenhuma transação ativa. ' +
    'Execute BeginTransaction antes da operação.');
end;

procedure TIBXDatabaseConnection.BeginTransaction(AIsolation: TTransactionIsolation);
begin
  if not FConnection.Connected then
    raise Exception.Create('A conexão com o banco está fechada.');

  if FTransaction.InTransaction then
    raise Exception.Create('Já existe uma transação ativa.');

  FTransaction.Params.Clear;
  case AIsolation of
    tiSnapshot: FTransaction.Params.Add('concurrency');
    tiReadCommitted:
    begin
      FTransaction.Params.Add('read_committed');
      FTransaction.Params.Add('rec_version');
    end;
  else
    raise EArgumentException.Create('Isolamento de transacao invalido.');
  end;
  FTransaction.Params.Add('wait');
  if FReadOnly then
    FTransaction.Params.Add('read')
  else
    FTransaction.Params.Add('write');
  FTransaction.StartTransaction;
  FIsolation := AIsolation;
  Inc(FVersion);
end;

procedure TIBXDatabaseConnection.Commit;
begin
  CheckTransaction;
  FTransaction.Commit;
end;

procedure TIBXDatabaseConnection.Rollback;
begin
  if FTransaction.InTransaction then
    FTransaction.Rollback;
end;

function TIBXDatabaseConnection.OpenReadSession: IDatabaseConnection;
var
  LSession: TIBXDatabaseConnection;
begin
  LSession := TIBXDatabaseConnection.Create(FConnection);
  Result := LSession;
  LSession.FReadOnly := True;
  LSession.BeginTransaction(tiSnapshot);
end;

function TIBXDatabaseConnection.InTransaction: Boolean;
begin
  Result := FTransaction.InTransaction;
end;

function TIBXDatabaseConnection.TransactionIsolation: TTransactionIsolation;
begin
  CheckTransaction;
  Result := FIsolation;
end;

function TIBXDatabaseConnection.TransactionVersion: Int64;
begin
  CheckTransaction;
  Result := FVersion;
end;

procedure TIBXDatabaseConnection.BindParams(
  const ASQL: TIBSQL;
  const AParams: TParams);
var
  LParam: TDbParam;
  LSQLParam: TIBXSQLVAR;
begin
  for LParam in AParams do
  begin
    LSQLParam := ASQL.ParamByName(LParam.Name);

    if VarIsNull(LParam.Value) or
       VarIsEmpty(LParam.Value) then
      LSQLParam.IsNull := True
    else
      LSQLParam.AsVariant := LParam.Value;
  end;
end;

function TIBXDatabaseConnection.Execute(
  const ASQL: string;
  const AParams: TParams): Int64;
var
  LSQL: TIBSQL;
begin
  CheckTransaction;

  LSQL := TIBSQL.Create(nil);
  try
    LSQL.Database := FConnection;
    LSQL.Transaction := FTransaction;
    LSQL.SQL.Text := ASQL;

    LSQL.Prepare;
    BindParams(LSQL, AParams);

    LSQL.ExecQuery;
    Inc(FVersion);
    Result := LSQL.RowsAffected;
  finally
    LSQL.Free;
  end;
end;

function TIBXDatabaseConnection.Query(const ASQL: string;
  const AParams: TParams; AMaxRows: Integer): TObjectList<TValues>;
var
  LSQL: TIBSQL;
  LField: TIBXSQLVAR;
  LValues: TValues;
  LValue: Variant;
  LBytes: TBytes;
  LBuffer: Pointer;
  LScale: Integer;
  I: Integer;
begin
  if AMaxRows < 0 then
    raise EArgumentException.Create(
      'O limite de registros nao pode ser negativo.');

  CheckTransaction;

  Result := TObjectList<TValues>.Create(True);
  try
    LSQL := TIBSQL.Create(nil);
    try
      LSQL.Database := FConnection;
      LSQL.Transaction := FTransaction;
      LSQL.SQL.Text := ASQL;
      LSQL.Prepare;
      BindParams(LSQL, AParams);
      LSQL.ExecQuery;

      while not LSQL.Eof do
      begin
        LValues := TValues.Create(TIStringComparer.Ordinal);
        try
          for I := 0 to LSQL.FieldCount - 1 do
          begin
            LField := LSQL.Fields[I];

            if LField.IsNull then
              LValue := Null
            else
            begin
              case LField.SQLType of
                SQL_TEXT, SQL_VARYING:
                  LValue := LField.AsString;

                SQL_SHORT, SQL_LONG, SQL_INT64:
                begin
                  LScale := LField.SqlVar.SqlScale;

                  if LScale = 0 then
                    LValue := LField.AsInt64
                  else if (LScale >= -4) and (LScale < 0) then
                    LValue := LField.AsCurrency
                  else
                    LValue := VarFMTBcdCreate(LField.AsBcd);
                end;

                SQL_FLOAT, SQL_DOUBLE, SQL_D_FLOAT:
                  LValue := LField.AsDouble;

                SQL_TIMESTAMP, SQL_TYPE_DATE, SQL_TYPE_TIME:
                  LValue := VarFromDateTime(LField.AsDateTime);

                SQL_BOOLEAN:
                  LValue := LField.AsBoolean;

                SQL_BLOB:
                begin
                  if LField.SqlVar.SqlSubtype = isc_blob_text then
                    LValue := LField.AsString
                  else
                  begin
                    LBytes := LField.AsBytes;

                    LValue := VarArrayCreate(
                      [0, Length(LBytes) - 1], varByte);

                    if Length(LBytes) > 0 then
                    begin
                      LBuffer := VarArrayLock(LValue);
                      try
                        Move(LBytes[0], LBuffer^, Length(LBytes));
                      finally
                        VarArrayUnlock(LValue);
                      end;
                    end;
                  end;
                end;

              else
                raise EConvertError.CreateFmt(
                  'Tipo SQL %d nao suportado no campo "%s".',
                  [LField.SQLType, LField.Name]);
              end;
            end;

            LValues.AddOrSetValue(LField.Name, LValue);
          end;

          Result.Add(LValues);
        except
          LValues.Free;
          raise;
        end;

        if (AMaxRows > 0) and (Result.Count >= AMaxRows) then
          Break;

        LSQL.Next;
      end;
    finally
      LSQL.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TIBXDatabaseConnection.ExecuteWithReturn(
  const ASQL: string;
  const AParams: TParams): TValues;
var
  LSQL: TIBSQL;
  I: Integer;
  LField: TIBXSQLVAR;
  LValue: Variant;
  LBytes: TBytes;
  LBuffer: Pointer;
  LScale: Integer;
begin
  CheckTransaction;

  Result := TValues.Create(TIStringComparer.Ordinal);
  try
    LSQL := TIBSQL.Create(nil);
    try
      LSQL.Database := FConnection;
      LSQL.Transaction := FTransaction;
      LSQL.SQL.Text := ASQL;

      LSQL.Prepare;
      BindParams(LSQL, AParams);
      LSQL.ExecQuery;
      Inc(FVersion);

      if (LSQL.FieldCount = 0) or
         ((LSQL.SQLType = SQLSelect) and LSQL.Eof) then
        raise Exception.Create('O comando não retornou registros.');

      for I := 0 to LSQL.FieldCount - 1 do
      begin
        LField := LSQL.Fields[I];

        if LField.IsNull then
          LValue := Null
        else
        begin
          case LField.SQLType of
            SQL_TEXT, SQL_VARYING:
              LValue := LField.AsString;

            SQL_SHORT, SQL_LONG, SQL_INT64:
            begin
              LScale := LField.SqlVar.SqlScale;

              if LScale = 0 then
                LValue := LField.AsInt64
              else if (LScale >= -4) and (LScale < 0) then
                LValue := LField.AsCurrency
              else
                LValue := VarFMTBcdCreate(LField.AsBcd);
            end;

            SQL_FLOAT, SQL_DOUBLE, SQL_D_FLOAT:
              LValue := LField.AsDouble;

            SQL_TIMESTAMP, SQL_TYPE_DATE, SQL_TYPE_TIME:
              LValue := VarFromDateTime(LField.AsDateTime);

            SQL_BOOLEAN:
              LValue := LField.AsBoolean;

            SQL_BLOB:
            begin
              if LField.SqlVar.SqlSubtype = isc_blob_text then
                LValue := LField.AsString
              else
              begin
                LBytes := LField.AsBytes;

                LValue := VarArrayCreate(
                  [0, Length(LBytes) - 1], varByte);

                if Length(LBytes) > 0 then
                begin
                  LBuffer := VarArrayLock(LValue);
                  try
                    Move(LBytes[0], LBuffer^, Length(LBytes));
                  finally
                    VarArrayUnlock(LValue);
                  end;
                end;
              end;
            end;

          else
            raise EConvertError.CreateFmt(
              'Tipo SQL %d nao suportado no campo "%s".',
              [LField.SQLType, LField.Name]);
          end;
        end;

        Result.AddOrSetValue(LField.Name, LValue);
      end;
    finally
      LSQL.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.

