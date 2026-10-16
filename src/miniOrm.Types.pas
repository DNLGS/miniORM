unit miniOrm.Types;

interface

uses
  Generics.Collections, Generics.Defaults, RTTI, SysUtils, Variants;

type
  TSortOrder = (soAsc, soDesc);

  TComparisonOperator = (
    coEq,           // =
    coDiff,         // <>
    coGreater,      // >
    coGreaterEq,    // >=
    coLess,         // <
    coLessEq,       // <=
    coLike,         // LIKE
    coNotLike,      // NOT LIKE
    coIn,           // IN
    coNotIn,        // NOT IN
    coBetween,      // BETWEEN
    coNotBetween,   // NOT BETWEEN
    coIsNull,       // IS NULL
    coIsNotNull);   // IS NOT NULL


  TDbOperation = (dbInsert, dbUpdate, dbDelete);

  TDbParam = record
    Name: string;
    Value: Variant;
  end;

  TParams = TArray<TDbParam>;
  TValues = TDictionary<String,Variant>;

  TTransactionIsolation = (
    tiReadCommitted,
    tiSnapshot);

  TTransactionOptions = record
    Isolation: TTransactionIsolation;
    Wait: Boolean;
    LockTimeout: Integer;
    ReadOnly: Boolean;
  end;

  THasManyMetadata = Class
  private
    FCollectionProperty: TRttiProperty;
    FParentProperty: string;
    FChildProperty: string;
  public
    property CollectionProperty: TRttiProperty read FCollectionProperty;
    property ParentProperty: String read FParentProperty;
    property ChildProperty: String read FChildProperty;
    constructor Create(const ACollectionProp : TRttiProperty;
      AParentProp, AChildProp : String);
  end;

  TColumnMetadata = class
  private
    FColumnName: string;
    FProperty: TRttiProperty;
    FIsPK: Boolean;
    FIsAutoIncrement: Boolean;
    FIsNotNull: Boolean;
    FDefault: Variant;
    FMaxLength: Integer;
    FRaiseOnMaxLength: Boolean;

  public
    constructor Create(const AColumnName: string; AProperty: TRttiProperty;
      AIsPK, AIsAutoIncrement, AIsNotNull: Boolean; ADefaultValue : Variant; AMaxLength: Integer = 0;
      ARaiseOnMaxLength: Boolean = False);
    property ColumnName: string read FColumnName;
    property &Property: TRttiProperty read FProperty;
    property IsPK: Boolean read FIsPK;
    property IsAutoIncrement: Boolean read FIsAutoIncrement;
    property IsNotNull: Boolean read FIsNotNull;
    property DefaultValue: Variant read FDefault;
    property MaxLength: Integer read FMaxLength;
    property RaiseOnMaxLength: Boolean read FRaiseOnMaxLength;
  end;

  TEntityMetadata = class
  private
    FEntityClass: TClass;
    FTableName: string;
    FContext: TRttiContext;
    FColumns: TDictionary<string, TColumnMetadata>;
    FOrderedColumns: TObjectList<TColumnMetadata>;
    FHasManyList : TObjectList<THasManyMetadata>;
  public
    constructor Create(AClass: TClass);
    destructor Destroy; override;
    function GetColumn(const APropertyName: string): TColumnMetadata;
    function GetEnumerator: TEnumerator<TColumnMetadata>;
    property EntityClass: TClass read FEntityClass;
    property TableName: string read FTableName;
    property HasManyList: TObjectList<THasManyMetadata> read FHasManyList;
  end;

implementation

uses
  miniOrm.Attributes;

{ TColumnMetadata }

constructor TColumnMetadata.Create(const AColumnName: string;
  AProperty: TRttiProperty; AIsPK, AIsAutoIncrement, AIsNotNull: Boolean;
  ADefaultValue : Variant; AMaxLength: Integer; ARaiseOnMaxLength: Boolean);
begin
  inherited Create;
  FColumnName := AColumnName;
  FProperty := AProperty;
  FIsPK := AIsPK;
  FIsAutoIncrement := AIsAutoIncrement;
  FIsNotNull := AIsNotNull;
  FDefault := ADefaultValue;
  FMaxLength := AMaxLength;
  FRaiseOnMaxLength := ARaiseOnMaxLength;
end;

{ TEntityMetadata }

constructor TEntityMetadata.Create(AClass: TClass);
var
  LType: TRttiType;
  LProp: TRttiProperty;
  LAttribute: TCustomAttribute;
  LColumn, LExisting: TColumnMetadata;
  LColumnName: string;
  LDefaultValue : Variant;
  LMaxLength: Integer;
  LRaiseOnMaxLength: Boolean;
  LHasMany : THasManyMetadata;
  LIsPK, LIsAutoIncrement, LIsNotNull, LMapped, LIgnored: Boolean;
begin
  inherited Create;
  if AClass = nil then
    raise EArgumentNilException.Create('A classe da entidade não pode ser nil.');

  FEntityClass := AClass;
  FContext := TRttiContext.Create;
  FColumns := TDictionary<string, TColumnMetadata>.Create(TIStringComparer.Ordinal);
  FOrderedColumns := TObjectList<TColumnMetadata>.Create(True);
  LType := FContext.GetType(AClass);
  FHasManyList := TObjectList<THasManyMetadata>.Create(True);
  if LType = nil then
    raise Exception.CreateFmt('%s: RTTI indisponível.', [AClass.ClassName]);

  for LAttribute in LType.GetAttributes do
    if LAttribute is Table then
    begin
      FTableName := Trim(Table(LAttribute).Name);
      Break;
    end;

  if FTableName = '' then
    raise Exception.CreateFmt('%s: informe [Table].', [AClass.ClassName]);

  for LProp in LType.GetProperties do
  begin
    LColumnName := '';
    LIsPK := False;
    LIsAutoIncrement := False;
    LIsNotNull := False;
    LMapped := False;
    LIgnored := False;
    LDefaultValue := Null;
    LMaxLength := 0;
    LRaiseOnMaxLength := False;
    LHasMany := nil;

    for LAttribute in LProp.GetAttributes do
    begin
      if LAttribute is Ignore then
        LIgnored := True
      else if LAttribute is HasMany then
        LHasMany := THasManyMetadata.Create(LProp,
          HasMany(LAttribute).ParentProperty,
          HasMany(LAttribute).ChildProperty)
      else if LAttribute is Column then
      begin
        LColumnName := Trim(Column(LAttribute).Name);
        LMapped := True;
      end
      else if LAttribute is PK then
        LIsPK := True
      else if LAttribute is AutoIncrement then
        LIsAutoIncrement := True
      else if LAttribute is NotNull then
        LIsNotNull := True
      else if LAttribute is MaxLength then
      begin
        LMaxLength := MaxLength(LAttribute).Value;
        LRaiseOnMaxLength := MaxLength(LAttribute).RaiseEx;
      end
      else if LAttribute is DefaultValue then
        LDefaultValue := DefaultValue(LAttribute).Value;
    end;

    if LIgnored then
    begin
      LHasMany.Free;
      Continue;
    end;

    if LHasMany <> nil then
    begin
      try
        if (Trim(LHasMany.ParentProperty) = '') or
          (Trim(LHasMany.ChildProperty) = '') then
          raise EArgumentException.CreateFmt(
            '%s.%s: informe as propriedades pai e filha.',
            [AClass.ClassName, LProp.Name]);

        if LMapped then
          raise Exception.CreateFmt(
            '%s.%s: nao combine [Column] e [HasMany].',
            [AClass.ClassName, LProp.Name]);

        if not LProp.IsReadable then
          raise Exception.CreateFmt(
            '%s.%s: propriedade nao pode ser lida.',
            [AClass.ClassName, LProp.Name]);

        FHasManyList.Add(LHasMany);
      except
        LHasMany.Free;
        raise;
      end;

      Continue;
    end;

    if not LMapped then
      Continue;

    if not LProp.IsReadable then
      raise Exception.CreateFmt(
        '%s.%s: propriedade nao pode ser lida.',
        [AClass.ClassName, LProp.Name]);

    if LColumnName = '' then
      raise Exception.CreateFmt('%s.%s: nome da coluna vazio.',
        [AClass.ClassName, LProp.Name]);

    for LExisting in FOrderedColumns do
      if SameText(LExisting.ColumnName, LColumnName) then
        raise Exception.CreateFmt('%s: coluna "%s" duplicada.',
          [AClass.ClassName, LColumnName]);

    LColumn := TColumnMetadata.Create(LColumnName, LProp, LIsPK,
      LIsAutoIncrement, LIsNotNull, LDefaultValue, LMaxLength, LRaiseOnMaxLength);
    try
      FOrderedColumns.Add(LColumn);
    except
      LColumn.Free;
      raise;
    end;
    FColumns.Add(LProp.Name, LColumn);
  end;
end;

destructor TEntityMetadata.Destroy;
begin
  FColumns.Free;
  FOrderedColumns.Free;
  FContext.Free;
  FHasManyList.Free;
  inherited Destroy;
end;

function TEntityMetadata.GetColumn(
  const APropertyName: string): TColumnMetadata;
begin
  if not FColumns.TryGetValue(APropertyName, Result) then
    raise Exception.CreateFmt('%s: propriedade "%s" não está mapeada.',
      [FEntityClass.ClassName, APropertyName]);
end;

function TEntityMetadata.GetEnumerator: TEnumerator<TColumnMetadata>;
begin
  Result := FOrderedColumns.GetEnumerator;
end;

{ THasManyMetadata }

constructor THasManyMetadata.Create(const ACollectionProp: TRttiProperty;
  AParentProp, AChildProp: String);
begin
  FCollectionProperty := ACollectionProp;
  FParentProperty := AParentProp;
  FChildProperty := AChildProp;
end;

end.
