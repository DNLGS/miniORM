unit miniOrm.EntitySQLService;

interface

uses
  miniOrm.Types, SysUtils, TypInfo, Variants, Rtti;

type
  TEntitySQLService = class
  private
    class function GetPKWhereSQL(AMetadata: TEntityMetadata): string; static;
    class function GetPKReturningSQL(AMetadata: TEntityMetadata): string; static;
    class function IsNullValue(const AValue: TValue): Boolean; static;
  public
    class function GetInsertSQL(AMetadata: TEntityMetadata): string; static;
    class function GetUpdateSQL(AMetadata: TEntityMetadata): string; static;
    class function GetDeleteSQL(AMetadata: TEntityMetadata): string; static;
    class function GetValues(const AOperation: TDbOperation;
      const AObject: TObject; AMetadata: TEntityMetadata): TParams; static;
    class procedure ApplyUpdates(const AObject: TObject;
      AMetadata: TEntityMetadata;const AValues: TValues); static;
  end;

implementation

class function TEntitySQLService.GetPKWhereSQL(
  AMetadata: TEntityMetadata): string;
var
  LColumn: TColumnMetadata;
begin
  Result := '';
  for LColumn in AMetadata do
    if LColumn.IsPK then
    begin
      if Result <> '' then
        Result := Result + ' AND ';
      Result := Result + LColumn.ColumnName + ' = :' + LColumn.ColumnName;
    end;
  if Result = '' then
    raise Exception.CreateFmt('%s: nenhuma PK mapeada.',
      [AMetadata.EntityClass.ClassName]);
end;

class function TEntitySQLService.GetPKReturningSQL(
  AMetadata: TEntityMetadata): string;
var
  LColumn: TColumnMetadata;
begin
  Result := '';
  for LColumn in AMetadata do
    if LColumn.IsPK then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + LColumn.ColumnName;
    end;
  if Result = '' then
    raise Exception.CreateFmt('%s: nenhuma PK mapeada.',
      [AMetadata.EntityClass.ClassName]);
end;

class function TEntitySQLService.GetInsertSQL(
  AMetadata: TEntityMetadata): string;
var
  LColumn: TColumnMetadata;
  LFields, LValues, LSeparator: string;
begin
  if AMetadata = nil then
    raise EArgumentNilException.Create('Os metadados não podem ser nil.');
  LFields := '';
  LValues := '';
  LSeparator := '';
  for LColumn in AMetadata do
  begin
    if LColumn.IsAutoIncrement then
      Continue;
    LFields := LFields + LSeparator + LColumn.ColumnName;
    LValues := LValues + LSeparator + ':' + LColumn.ColumnName;
    LSeparator := ', ';
  end;
  if LFields = '' then
    raise Exception.CreateFmt('%s: nenhuma coluna disponível para INSERT.',
      [AMetadata.EntityClass.ClassName]);
  Result := Format('INSERT INTO %s (%s) VALUES (%s) RETURNING %s',
    [AMetadata.TableName, LFields, LValues, GetPKReturningSQL(AMetadata)]);
end;

class function TEntitySQLService.GetUpdateSQL(
  AMetadata: TEntityMetadata): string;
var
  LColumn: TColumnMetadata;
  LFields: string;
begin
  if AMetadata = nil then
    raise EArgumentNilException.Create('Os metadados não podem ser nil.');
  LFields := '';
  for LColumn in AMetadata do
  begin
    if LColumn.IsPK or LColumn.IsAutoIncrement then
      Continue;
    if LFields <> '' then
      LFields := LFields + ', ';
    LFields := LFields + LColumn.ColumnName + ' = :' + LColumn.ColumnName;
  end;
  if LFields = '' then
    raise Exception.CreateFmt('%s: nenhuma coluna disponível para UPDATE.',
      [AMetadata.EntityClass.ClassName]);
  Result := Format('UPDATE %s SET %s WHERE %s',
    [AMetadata.TableName, LFields, GetPKWhereSQL(AMetadata)]);
end;

class function TEntitySQLService.GetValues(const AOperation: TDbOperation;
  const AObject: TObject; AMetadata: TEntityMetadata): TParams;
var
  LType: PTypeInfo;
  LObj: TColumnMetadata;
  LValue: TValue;
  LCount: Integer;
  LInclude: Boolean;
  LText: string;

  procedure AddParam(const AObj: TColumnMetadata);
  begin
    LValue := AObj.&Property.GetValue(AObject);

    // Defaults so substituem valores ausentes no INSERT, nunca zero ou string vazia.
    if (AOperation = dbInsert) and IsNullValue(LValue) and
      not VarIsNull(AObj.DefaultValue) and not VarIsEmpty(AObj.DefaultValue) then
      LValue := TValue.From<Variant>(AObj.DefaultValue);

    if IsNullValue(LValue) and
       (AObj.IsNotNull or
        ((AOperation <> dbInsert) and AObj.IsPK)) then
      raise Exception.CreateFmt(
        'O campo "%s" é obrigatório.',
        [AObj.ColumnName]);

    SetLength(Result, LCount + 1);

    Result[LCount].Name := AObj.ColumnName;
    LType := AObj.&Property.PropertyType.Handle;

    if IsNullValue(LValue) then
      Result[LCount].Value := Null
    else if LValue.Kind = tkVariant then
      Result[LCount].Value := LValue.AsVariant
    else if LType = TypeInfo(TDateTime) then
      Result[LCount].Value := VarFromDateTime(LValue.AsExtended)
    else
    begin
      case LType.Kind of
        tkInteger,
        tkInt64:
          Result[LCount].Value := LValue.AsInt64;

        tkChar,
        tkWChar,
        tkString,
        tkLString,
        tkWString,
        tkUString:
        begin
          Result[LCount].Value := LValue.AsString;
        end;

        tkFloat:
        begin
          if GetTypeData(LType)^.FloatType = ftCurr then
            Result[LCount].Value := LValue.AsCurrency
          else
            Result[LCount].Value := LValue.AsExtended;
        end;

        tkEnumeration:
          begin
            if LType = TypeInfo(Boolean) then
              Result[LCount].Value := LValue.AsBoolean
            else
              Result[LCount].Value := LValue.AsOrdinal;
          end;

        tkVariant:
          Result[LCount].Value := LValue.AsVariant;

      else
        raise Exception.CreateFmt(
          'Tipo de propriedade não suportado: "%s".',
          [AObj.ColumnName]);
      end;
    end;

    if VarIsStr(Result[LCount].Value) and
      (VarToStr(Result[LCount].Value) = '') and
      (AObj.IsNotNull or ((AOperation <> dbInsert) and AObj.IsPK)) then
      raise EArgumentException.CreateFmt('O campo "%s" e obrigatorio.', [AObj.ColumnName]);

    if VarIsStr(Result[LCount].Value) and (AObj.MaxLength > 0) then
    begin
      LText := Result[LCount].Value;
      if Length(LText) > AObj.MaxLength then
      begin
        if AObj.RaiseOnMaxLength or AObj.IsPK then
          raise EArgumentException.CreateFmt('O campo "%s" excede %d caracteres.',
            [AObj.ColumnName, AObj.MaxLength]);
        Result[LCount].Value := Copy(LText, 1, AObj.MaxLength);
      end;
    end;
    Inc(LCount);
  end;

begin
  SetLength(Result, 0);
  LCount := 0;

  if AObject = nil then
  raise EArgumentNilException.Create('Informe o objeto.');

  if AMetadata = nil then
    raise EArgumentNilException.Create('Informe os metadados.');

  if not AObject.InheritsFrom(AMetadata.EntityClass) then
    raise EArgumentException.Create(
      'Os metadados nao correspondem ao objeto.');

  for LObj in AMetadata do
  begin
    case AOperation of
      dbInsert:
        LInclude := not LObj.IsAutoIncrement;

      dbUpdate:
        LInclude :=
          not LObj.IsPK and
          not LObj.IsAutoIncrement;

      dbDelete:
        LInclude := False;
    else
      raise Exception.Create('Operação inválida.');
    end;

    if LInclude then
      AddParam(LObj);
  end;

  if AOperation in [dbUpdate, dbDelete] then
  begin
    for LObj in AMetadata do
    begin
      if LObj.IsPK then
        AddParam(LObj);
    end;
  end;
end;

class function TEntitySQLService.IsNullValue(const AValue: TValue): Boolean;
var
  LVariant: Variant;
begin
  Result := AValue.IsEmpty;

  if Result then
    Exit;

  if AValue.Kind = tkVariant then
  begin
    LVariant := AValue.AsVariant;

    Result :=
      VarIsNull(LVariant) or
      VarIsEmpty(LVariant);
  end;
end;

class procedure TEntitySQLService.ApplyUpdates(
  const AObject: TObject;
  AMetadata: TEntityMetadata;
  const AValues: TValues);
var
  LColumn: TColumnMetadata;
  LValue: Variant;
begin
  if AObject = nil then
    raise EArgumentNilException.Create('O objeto não pode ser nil.');

  if AMetadata = nil then
    raise EArgumentNilException.Create('Os metadados não podem ser nil.');

  if AValues = nil then
    raise EArgumentNilException.Create('Os valores não podem ser nil.');

  if not AObject.InheritsFrom(AMetadata.EntityClass) then
    raise EArgumentException.Create(
      'Os metadados não correspondem à classe do objeto.');

  for LColumn in AMetadata do
  begin
    if not AValues.TryGetValue(LColumn.ColumnName, LValue) then
      Continue;

    if not LColumn.&Property.IsWritable then
      raise Exception.CreateFmt(
        '%s.%s: propriedade não pode ser escrita.',
        [AObject.ClassName, LColumn.&Property.Name]);

    if (VarIsNull(LValue) or VarIsEmpty(LValue)) and LColumn.IsNotNull then
      raise EConvertError.CreateFmt('A coluna "%s" obrigatoria retornou NULL.',
        [LColumn.ColumnName]);

    if LColumn.&Property.PropertyType.TypeKind = tkVariant then
      LColumn.&Property.SetValue(AObject, TValue.From<Variant>(LValue))
    else if VarIsNull(LValue) or VarIsEmpty(LValue) then
      raise EConvertError.CreateFmt(
        '%s.%s: NULL exige uma propriedade Variant.',
        [AObject.ClassName, LColumn.&Property.Name])
    else
      LColumn.&Property.SetValue(AObject, TValue.FromVariant(LValue));
  end;
end;

class function TEntitySQLService.GetDeleteSQL(
  AMetadata: TEntityMetadata): string;
begin
  if AMetadata = nil then
    raise EArgumentNilException.Create('Os metadados não podem ser nil.');
  Result := Format('DELETE FROM %s WHERE %s',
    [AMetadata.TableName, GetPKWhereSQL(AMetadata)]);
end;

end.
