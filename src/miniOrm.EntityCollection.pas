unit miniOrm.EntityCollection;

interface

uses
  SysUtils, Variants, Generics.Collections,
  miniOrm.DbObjectBase, miniOrm.EntityMetadataCache, miniOrm.EntitySQLService,
  miniOrm.Types, miniOrm.DatabaseConnection.Intf;

type
  TEntityCollection = class
  public
    constructor Create; virtual;
    procedure Initialize(const AConnection: IDatabaseConnection;
      AParent: TDbObjectBase; ARelation: THasManyMetadata); virtual; abstract;
  end;

  TEntityCollectionClass = class of TEntityCollection;

  TEntityCollectionBase<T: TDbObjectBase, constructor> = class(TEntityCollection)
  private
    FEntityChildClass: TClass;
    FConnection: IDatabaseConnection;
    FSQL: string;
    FParams: TParams;
    // Preserva as instancias ja entregues, mesmo ao acessar outra pagina.
    FPages: TObjectDictionary<Integer, TObjectList<T>>;
    FCount: Integer;
    FReadVersion: Int64;
    FParent: TDbObjectBase;
    FRelation: THasManyMetadata;
    FParentValue: Variant;
    procedure CheckInitialized;
    function GetOrderSQL: string;
    function GetPage(APageIndex: Integer): TObjectList<T>;
    function GetCount: Integer;
    function GetItem(Index: Integer): T;
    const MAX_ROW = 50;
  public
    constructor Create; overload; override;
    constructor Create(const AConnection: IDatabaseConnection;
      const ASQL: string; const AParams: TParams); reintroduce; overload;
    destructor Destroy; override;
    procedure Initialize(const AConnection: IDatabaseConnection;
      AParent: TDbObjectBase; ARelation: THasManyMetadata); override;
    class function LoadEntities(const AConnection: IDatabaseConnection;
      const ASQL: string; const AParams: TParams;
      AMaxRows: Integer): TObjectList<T>; static;
    function GetEnumerator: TEnumerator<T>;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: T read GetItem; default;
  end;

  TEntityCollectionEnumerator<T: TDbObjectBase, constructor> = class(TEnumerator<T>)
  private
    FCollection: TEntityCollectionBase<T>;
    FIndex: Integer;
  protected
    function DoGetCurrent: T; override;
    function DoMoveNext: Boolean; override;
  public
    constructor Create(ACollection: TEntityCollectionBase<T>);
  end;

implementation

constructor TEntityCollection.Create;
begin
  inherited Create;
end;

constructor TEntityCollectionBase<T>.Create;
begin
  inherited Create;
  FEntityChildClass := TClass(T);
  FCount := -1;
  FPages := TObjectDictionary<Integer, TObjectList<T>>.Create([doOwnsValues]);
end;

constructor TEntityCollectionBase<T>.Create(
  const AConnection: IDatabaseConnection; const ASQL: string;
  const AParams: TParams);
begin
  Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Informe a conexao para carregar a colecao.');
  if Trim(ASQL) = '' then
    raise EArgumentException.Create('Informe a consulta da colecao.');
  FConnection := AConnection;
  FSQL := ASQL;
  FParams := Copy(AParams, 0, Length(AParams));
end;

destructor TEntityCollectionBase<T>.Destroy;
begin
  FPages.Free;
  inherited Destroy;
end;

procedure TEntityCollectionBase<T>.Initialize(
  const AConnection: IDatabaseConnection; AParent: TDbObjectBase;
  ARelation: THasManyMetadata);
var
  LMetadata: TEntityMetadata;
  LColumn, LChildColumn: TColumnMetadata;
  LColumns: string;
  LValue: Variant;
begin
  if AConnection = nil then
    raise EArgumentNilException.Create('Informe a conexao do relacionamento.');
  if (AParent = nil) or (ARelation = nil) then
    raise EArgumentNilException.Create('Informe o pai e o relacionamento.');
  if (FConnection <> nil) and
    ((FParent <> AParent) or (FRelation <> ARelation) or (FCount >= 0)) then
    raise EInvalidOpException.Create('A colecao ja foi carregada ou pertence a outro pai.');
  LMetadata := TEntityMetadataCache.GetOrCreateEntity(FEntityChildClass);
  LChildColumn := LMetadata.GetColumn(ARelation.ChildProperty);
  LValue := AParent.Metadata.GetColumn(ARelation.ParentProperty).
    &Property.GetValue(AParent).AsVariant;
  LColumns := '';
  for LColumn in LMetadata do
  begin
    if LColumns <> '' then
      LColumns := LColumns + ', ';
    LColumns := LColumns + LColumn.ColumnName;
  end;
  FSQL := 'SELECT ' + LColumns + ' FROM ' + LMetadata.TableName;
  SetLength(FParams, 0);
  // Uma chave ausente nao deve buscar todos os filhos com chave NULL.
  if VarIsNull(LValue) or VarIsEmpty(LValue) then
    FSQL := FSQL + ' WHERE 1 = 0'
  else
  begin
    FSQL := FSQL + ' WHERE ' + LChildColumn.ColumnName + ' = :parent_value';
    SetLength(FParams, 1);
    FParams[0].Name := 'parent_value';
    FParams[0].Value := LValue;
  end;
  FParent := AParent;
  FRelation := ARelation;
  FParentValue := LValue;
  FConnection := AConnection;
end;

procedure TEntityCollectionBase<T>.CheckInitialized;
var
  LValue: Variant;
  LVersion: Int64;
begin
  if (FConnection = nil) or (Trim(FSQL) = '') then
    raise EInvalidOpException.Create('A colecao ainda nao foi inicializada.');
  if FConnection.TransactionIsolation <> tiSnapshot then
    raise EInvalidOpException.Create('A paginacao exige uma transacao snapshot.');
  Assert((FPages.Count = 0) or (FCount >= 0),
    'Paginas em cache exigem uma contagem vinculada a leitura.');
  LVersion := FConnection.TransactionVersion;
  if (FReadVersion <> 0) and (FReadVersion <> LVersion) then
    raise EInvalidOpException.Create(
      'A transacao ou seus dados mudaram. Recrie a colecao antes de continuar.');
  if FParent <> nil then
  begin
    // A colecao de relacionamento nao deve sobreviver ao pai.
    if FCount < 0 then
      Initialize(FConnection, FParent, FRelation)
    else
    begin
      LValue := FParent.Metadata.GetColumn(FRelation.ParentProperty).
        &Property.GetValue(FParent).AsVariant;
      if not VarSameValue(LValue, FParentValue) then
        raise EInvalidOpException.Create('A chave do pai mudou. Recrie a colecao.');
    end;
  end;
  FReadVersion := LVersion;
end;

function TEntityCollectionBase<T>.GetOrderSQL: string;
var
  LMetadata: TEntityMetadata;
  LColumn: TColumnMetadata;
begin
  Result := '';
  LMetadata := TEntityMetadataCache.GetOrCreateEntity(FEntityChildClass);
  for LColumn in LMetadata do
    if LColumn.IsPK then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + 'ORM_PAGE.' + LColumn.ColumnName;
    end;
  if Result = '' then
    raise EInvalidOpException.CreateFmt(
      '%s: informe [PK] para ordenar a paginacao.', [FEntityChildClass.ClassName]);
end;

function TEntityCollectionBase<T>.GetCount: Integer;
var
  LRows: TObjectList<TValues>;
  LValue: Variant;
  LTotal: Int64;
begin
  CheckInitialized;
  if FCount < 0 then
  begin
    LRows := FConnection.Query(
      'SELECT COUNT(*) AS ORM_TOTAL FROM (' + FSQL + ') ORM_COUNT_SOURCE',
      FParams, 1);
    try
      if LRows = nil then
        raise EInvalidOpException.Create('A contagem deve retornar uma lista.');
      if LRows.Count <> 1 then
        raise EInvalidOpException.Create('A contagem deve retornar um registro.');
      if LRows[0] = nil then
        raise EInvalidOpException.Create('Registro de contagem invalido.');
      if not LRows[0].TryGetValue('ORM_TOTAL', LValue) then
        raise EInvalidOpException.Create('A consulta nao retornou ORM_TOTAL.');
      if VarIsNull(LValue) or VarIsEmpty(LValue) then
        raise EInvalidOpException.Create('A contagem nao pode ser nula.');
      LTotal := LValue;
      if (LTotal < 0) or (LTotal > MaxInt) then
        raise ERangeError.Create('A contagem excede o intervalo suportado pela colecao.');
      FCount := Integer(LTotal);
    finally
      LRows.Free;
    end;
  end;
  Result := FCount;
end;

function TEntityCollectionBase<T>.GetPage(APageIndex: Integer): TObjectList<T>;
var
  LFirst, LLast: Int64;
  LSQL: string;
begin
  CheckInitialized;
  if not FPages.TryGetValue(APageIndex, Result) then
  begin
    LFirst := Int64(APageIndex) * MAX_ROW + 1;
    LLast := LFirst + MAX_ROW - 1;
    LSQL := 'SELECT ORM_PAGE.* FROM (' + FSQL + ') ORM_PAGE ORDER BY ' +
      GetOrderSQL + ' ROWS ' + IntToStr(LFirst) + ' TO ' + IntToStr(LLast);
    Result := LoadEntities(FConnection, LSQL, FParams, MAX_ROW);
    try
      FPages.Add(APageIndex, Result);
    except
      Result.Free;
      raise;
    end;
  end;
end;

function TEntityCollectionBase<T>.GetItem(Index: Integer): T;
var
  LPage: TObjectList<T>;
  LOffset: Integer;
begin
  if (Index < 0) or (Index >= GetCount) then
    raise EArgumentOutOfRangeException.Create('Indice fora dos limites da colecao.');
  LPage := GetPage(Index div MAX_ROW);
  LOffset := Index mod MAX_ROW;
  if LOffset >= LPage.Count then
    raise EInvalidOpException.Create(
      'A pagina retornou menos registros que a contagem. Recrie a colecao em uma transacao consistente.');
  Result := LPage[LOffset];
end;

class function TEntityCollectionBase<T>.LoadEntities(
  const AConnection: IDatabaseConnection; const ASQL: string;
  const AParams: TParams; AMaxRows: Integer): TObjectList<T>;
var
  LRows: TObjectList<TValues>;
  LValues: TValues;
  LEntity: T;
begin
  if AConnection = nil then
    raise EArgumentNilException.Create('Informe a conexao para executar a consulta.');
  Result := TObjectList<T>.Create(True);
  try
    LRows := AConnection.Query(ASQL, AParams, AMaxRows);
    try
      if LRows = nil then
        raise EInvalidOpException.Create('A consulta deve retornar uma lista, mesmo que vazia.');
      if (AMaxRows > 0) and (LRows.Count > AMaxRows) then
        raise EInvalidOpException.Create('A consulta excedeu o limite de registros.');
      for LValues in LRows do
      begin
        LEntity := T.Create;
        try
          TEntitySQLService.ApplyUpdates(LEntity, LEntity.Metadata, LValues);
          LEntity.InitializeRelations(AConnection);
          Result.Add(LEntity);
        except
          LEntity.Free;
          raise;
        end;
      end;
    finally
      LRows.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TEntityCollectionBase<T>.GetEnumerator: TEnumerator<T>;
begin
  Result := TEntityCollectionEnumerator<T>.Create(Self);
end;

constructor TEntityCollectionEnumerator<T>.Create(
  ACollection: TEntityCollectionBase<T>);
begin
  inherited Create;
  FCollection := ACollection;
  FIndex := -1;
end;

function TEntityCollectionEnumerator<T>.DoGetCurrent: T;
begin
  Result := FCollection[FIndex];
end;

function TEntityCollectionEnumerator<T>.DoMoveNext: Boolean;
begin
  Result := FIndex < FCollection.Count - 1;
  if Result then
    Inc(FIndex)
  else
    FIndex := FCollection.Count;
end;

end.
