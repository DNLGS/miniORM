unit miniOrm.QueryBuilder;

interface

uses
  miniOrm.DbObjectBase, miniOrm.Types, miniOrm.DatabaseConnection.Intf,
  miniOrm.EntityCollection, Generics.Collections, TypInfo, SysUtils, Variants;

type
  IQueryBuilder<T: TDbObjectBase, constructor> = interface;

  TQueryConnector = (qcWhere, qcAnd, qcOr);

  IQueryComparisonTarget = interface
    ['{63EB14C9-A0BB-4816-88EA-74D0D16A132F}']
    procedure ApplyComparison(const APropertyName: string;
      AConnector: TQueryConnector; AComparison: TComparisonOperator;
      const AValue: Variant);
  end;

  TQueryComparison<T: TDbObjectBase, constructor> = record
  private
    FBuilder: IQueryBuilder<T>;
    FTarget: IQueryComparisonTarget;
    FPropertyName: string;
    FConnector: TQueryConnector;
    function Compare(AComparison: TComparisonOperator;
      const AValue: Variant): IQueryBuilder<T>;
  public
    class operator Equal(const AField: TQueryComparison<T>;
      const AValue: Variant): IQueryBuilder<T>;
    class operator NotEqual(const AField: TQueryComparison<T>;
      const AValue: Variant): IQueryBuilder<T>;
    class operator GreaterThan(const AField: TQueryComparison<T>;
      const AValue: Variant): IQueryBuilder<T>;
    class operator GreaterThanOrEqual(const AField: TQueryComparison<T>;
      const AValue: Variant): IQueryBuilder<T>;
    class operator LessThan(const AField: TQueryComparison<T>;
      const AValue: Variant): IQueryBuilder<T>;
    class operator LessThanOrEqual(const AField: TQueryComparison<T>;
      const AValue: Variant): IQueryBuilder<T>;
  end;

  IQueryBuilder<T: TDbObjectBase, constructor> = interface
    ['{0FFFE423-D2E3-4B3C-A9A5-0697E645C0EB}']
    function Where(const AFieldName: string): TQueryComparison<T>;
    function AndWhere(const AFieldName: string): TQueryComparison<T>;
    function OrWhere(const AFieldName: string): TQueryComparison<T>;
    function FirstOrDefault: T;
    function ToList: TEntityCollectionBase<T>;
  end;

  TQueryBuilder<T: TDbObjectBase, constructor> = class(TInterfacedObject,
    IQueryBuilder<T>, IQueryComparisonTarget)
  private
    FDatabaseConnection: IDatabaseConnection;
    FMetadata: TEntityMetadata;
    FWhereSQL: string;
    FParams: TParams;
    function SelectField(const AFieldName: string;
      AConnector: TQueryConnector): TQueryComparison<T>;
    procedure ApplyComparison(const APropertyName: string;
      AConnector: TQueryConnector; AComparison: TComparisonOperator;
      const AValue: Variant);
    procedure Build(out ASQL: string; out AParams: TParams);
  public
    constructor Create(const ADatabaseConnection: IDatabaseConnection = nil);
    class function New(const ADatabaseConnection: IDatabaseConnection = nil):
      IQueryBuilder<T>; static;
    function Where(const AFieldName: string): TQueryComparison<T>;
    function AndWhere(const AFieldName: string): TQueryComparison<T>;
    function OrWhere(const AFieldName: string): TQueryComparison<T>;
    function FirstOrDefault: T;
    function ToList: TEntityCollectionBase<T>;
  end;

implementation

uses
  miniOrm.EntityMetadataCache, miniOrm.EntitySQLService;

{ TQueryComparison<T> }

function TQueryComparison<T>.Compare(AComparison: TComparisonOperator;
  const AValue: Variant): IQueryBuilder<T>;
begin
  if (FBuilder = nil) or (FTarget = nil) or (FPropertyName = '') then
    raise EArgumentException.Create('Selecione um campo antes de comparar.');
  FTarget.ApplyComparison(FPropertyName, FConnector, AComparison, AValue);
  Result := FBuilder;
end;

class operator TQueryComparison<T>.Equal(const AField: TQueryComparison<T>;
  const AValue: Variant): IQueryBuilder<T>;
begin
  Result := AField.Compare(coEq, AValue);
end;

class operator TQueryComparison<T>.NotEqual(const AField: TQueryComparison<T>;
  const AValue: Variant): IQueryBuilder<T>;
begin
  Result := AField.Compare(coDiff, AValue);
end;

class operator TQueryComparison<T>.GreaterThan(const AField: TQueryComparison<T>;
  const AValue: Variant): IQueryBuilder<T>;
begin
  Result := AField.Compare(coGreater, AValue);
end;

class operator TQueryComparison<T>.GreaterThanOrEqual(
  const AField: TQueryComparison<T>; const AValue: Variant): IQueryBuilder<T>;
begin
  Result := AField.Compare(coGreaterEq, AValue);
end;

class operator TQueryComparison<T>.LessThan(const AField: TQueryComparison<T>;
  const AValue: Variant): IQueryBuilder<T>;
begin
  Result := AField.Compare(coLess, AValue);
end;

class operator TQueryComparison<T>.LessThanOrEqual(
  const AField: TQueryComparison<T>; const AValue: Variant): IQueryBuilder<T>;
begin
  Result := AField.Compare(coLessEq, AValue);
end;

{ TQueryBuilder<T> }

constructor TQueryBuilder<T>.Create(
  const ADatabaseConnection: IDatabaseConnection);
begin
  inherited Create;
  FDatabaseConnection := ADatabaseConnection;
  FMetadata := TEntityMetadataCache.GetOrCreateEntity(
    GetTypeData(TypeInfo(T))^.ClassType);
end;

class function TQueryBuilder<T>.New(
  const ADatabaseConnection: IDatabaseConnection): IQueryBuilder<T>;
begin
  Result := TQueryBuilder<T>.Create(ADatabaseConnection);
end;

function TQueryBuilder<T>.SelectField(const AFieldName: string;
  AConnector: TQueryConnector): TQueryComparison<T>;
begin
  Result.FPropertyName := FMetadata.GetColumn(AFieldName).&Property.Name;
  // As interfaces mantêm o builder vivo até a comparação ser aplicada.
  Result.FBuilder := Self;
  Result.FTarget := Self;
  Result.FConnector := AConnector;
end;

function TQueryBuilder<T>.Where(const AFieldName: string): TQueryComparison<T>;
begin
  Result := SelectField(AFieldName, qcWhere);
end;

function TQueryBuilder<T>.AndWhere(const AFieldName: string): TQueryComparison<T>;
begin
  Result := SelectField(AFieldName, qcAnd);
end;

function TQueryBuilder<T>.OrWhere(const AFieldName: string): TQueryComparison<T>;
begin
  Result := SelectField(AFieldName, qcOr);
end;

procedure TQueryBuilder<T>.ApplyComparison(const APropertyName: string;
  AConnector: TQueryConnector; AComparison: TComparisonOperator;
  const AValue: Variant);
var
  LColumn: TColumnMetadata;
  LWhereSQL, LCondition, LOperator, LConnector, LParamName: string;
  LParams: TParams;
  LIsNull: Boolean;
  LIndex: Integer;
begin
  LColumn := FMetadata.GetColumn(APropertyName);
  case AConnector of
    qcWhere: LConnector := '';
    qcAnd: LConnector := ' AND ';
    qcOr: LConnector := ' OR ';
  else
    raise EArgumentException.Create('Conector de consulta inválido.');
  end;
  case AComparison of
    coEq: LOperator := '=';
    coDiff: LOperator := '<>';
    coGreater: LOperator := '>';
    coGreaterEq: LOperator := '>=';
    coLess: LOperator := '<';
    coLessEq: LOperator := '<=';
  else
    raise EArgumentException.Create('Operador de comparação não suportado.');
  end;

  LIsNull := VarIsNull(AValue) or VarIsEmpty(AValue);
  if LIsNull then
  begin
    case AComparison of
      coEq: LOperator := 'IS NULL';
      coDiff: LOperator := 'IS NOT NULL';
    else
      raise EArgumentException.Create('NULL só pode ser comparado com = ou <>.');
    end;
  end
  else
    case VarType(AValue) of
      varSmallint, varInteger, varSingle, varDouble, varCurrency,
      varDate, varOleStr, varBoolean, varShortInt, varByte, varWord,
      varLongWord, varInt64, varString, varUString: ;
    else
      raise EArgumentException.Create('O valor do filtro deve ser um Variant escalar.');
    end;

  if AConnector = qcWhere then
  begin
    LWhereSQL := '';
    SetLength(LParams, 0);
  end
  else
  begin
    LWhereSQL := FWhereSQL;
    LParams := Copy(FParams, 0, Length(FParams));
  end;

  LCondition := LColumn.ColumnName + ' ' + LOperator;
  if not LIsNull then
  begin
    LIndex := Length(LParams);
    LParamName := 'p' + IntToStr(LIndex + 1);
    SetLength(LParams, LIndex + 1);
    LParams[LIndex].Name := LParamName;
    LParams[LIndex].Value := AValue;
    LCondition := LCondition + ' :' + LParamName;
  end;

  if LWhereSQL = '' then
    LWhereSQL := LCondition
  else
    LWhereSQL := '(' + LWhereSQL + LConnector + LCondition + ')';

  FWhereSQL := LWhereSQL;
  FParams := LParams;
end;

function TQueryBuilder<T>.FirstOrDefault: T;
var
  LSQL: string;
  LParams: TParams;
  LEntities: TObjectList<T>;
begin
  Result := nil;
  Build(LSQL, LParams);
  LEntities := TEntityCollectionBase<T>.LoadEntities(FDatabaseConnection, LSQL, LParams, 1);
  try
    if LEntities.Count > 0 then
      Result := LEntities.Extract(LEntities[0]);
  finally
    LEntities.Free;
  end;
end;

function TQueryBuilder<T>.ToList: TEntityCollectionBase<T>;
var
  LSQL: string;
  LParams: TParams;
begin
  if FDatabaseConnection = nil then
    raise EArgumentNilException.Create('Informe a conexao para executar a consulta.');
  Build(LSQL, LParams);
  // Captura a consulta pronta, sem depender do builder durante a carga tardia.
  Result := TEntityCollectionBase<T>.Create(FDatabaseConnection, LSQL, LParams);
end;

procedure TQueryBuilder<T>.Build(out ASQL: string; out AParams: TParams);
var
  LColumn: TColumnMetadata;
  LColumns: string;
begin
  ASQL := '';
  SetLength(AParams, 0);
  LColumns := '';
  for LColumn in FMetadata do
  begin
    if LColumns <> '' then
      LColumns := LColumns + ', ';
    LColumns := LColumns + LColumn.ColumnName;
  end;
  if LColumns = '' then
    raise EInvalidOpException.Create('A entidade não possui colunas mapeadas.');

  Assert((FWhereSQL <> '') or (Length(FParams) = 0),
    'A consulta possui parâmetros sem uma condição SQL.');
  ASQL := 'SELECT ' + LColumns + ' FROM ' + FMetadata.TableName;
  if FWhereSQL <> '' then
    ASQL := ASQL + ' WHERE ' + FWhereSQL;
  AParams := Copy(FParams, 0, Length(FParams));
end;

end.
