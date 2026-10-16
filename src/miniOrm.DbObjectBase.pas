unit miniOrm.DbObjectBase;

interface

uses
  miniOrm.Types, miniOrm.DatabaseConnection.Intf, Generics.Collections,
  Rtti,
  TypInfo,
  SysUtils,
  Variants;

{$M+}

type
  TDbObjectBase = class
  private
    FOwnedCollections: TObjectList<TObject>;
  protected
    FMetadata: TEntityMetadata;
  public
    constructor Create;
    destructor Destroy; override;
    procedure InitializeRelations(const AConnection: IDatabaseConnection);
    property Metadata: TEntityMetadata read FMetadata;
  end;

{$M-}

implementation

uses
  miniOrm.EntityMetadataCache, miniOrm.EntityCollection, miniOrm.EntitySQLService;

constructor TDbObjectBase.Create;
var
  LColumn: TColumnMetadata;
  LDefaults: TValues;
begin
  inherited Create;
  FMetadata := TEntityMetadataCache.GetOrCreateEntity(ClassType);
  LDefaults := TValues.Create;
  try
    for LColumn in FMetadata do
      if not VarIsNull(LColumn.DefaultValue) and not VarIsEmpty(LColumn.DefaultValue) then
        LDefaults.Add(LColumn.ColumnName, LColumn.DefaultValue);
    TEntitySQLService.ApplyUpdates(Self, FMetadata, LDefaults);
  finally
    LDefaults.Free;
  end;
end;

destructor TDbObjectBase.Destroy;
begin
  FOwnedCollections.Free;
  inherited Destroy;
end;

procedure TDbObjectBase.InitializeRelations(const AConnection: IDatabaseConnection);
var
  LRelation: THasManyMetadata;
  LType: TRttiInstanceType;
  LObject: TObject;
  LCollection: TEntityCollection;
  LCreated: Boolean;
  LCollectionValue: TValue;
begin
  if AConnection = nil then
    raise EArgumentNilException.Create('Informe a conexao dos relacionamentos.');
  for LRelation in FMetadata.HasManyList do
  begin
    if LRelation.CollectionProperty.PropertyType.TypeKind <> tkClass then
      raise EArgumentException.CreateFmt('%s.%s: HasMany exige uma colecao.',
        [ClassName, LRelation.CollectionProperty.Name]);
    LType := TRttiInstanceType(LRelation.CollectionProperty.PropertyType);
    if not LType.MetaclassType.InheritsFrom(TEntityCollection) then
      raise EArgumentException.CreateFmt('%s.%s: tipo de colecao invalido.',
        [ClassName, LRelation.CollectionProperty.Name]);
    LObject := LRelation.CollectionProperty.GetValue(Self).AsObject;
    LCreated := LObject = nil;
    if LCreated then
    begin
      if not LRelation.CollectionProperty.IsWritable then
        raise EArgumentException.CreateFmt('%s.%s: inicialize a colecao ou permita escrita.',
          [ClassName, LRelation.CollectionProperty.Name]);
      LCollection := TEntityCollectionClass(LType.MetaclassType).Create;
    end
    else
    begin
      if not LObject.InheritsFrom(LType.MetaclassType) then
        raise EArgumentException.Create('A instancia da colecao nao corresponde a propriedade.');
      LCollection := TEntityCollection(LObject);
    end;
    try
      LCollection.Initialize(AConnection, Self, LRelation);
      if LCreated then
      begin
        if FOwnedCollections = nil then
          FOwnedCollections := TObjectList<TObject>.Create(True);
        FOwnedCollections.Add(LCollection);
        LCreated := False;
        TValue.Make(@LCollection, LRelation.CollectionProperty.PropertyType.Handle,
          LCollectionValue);
        LRelation.CollectionProperty.SetValue(Self, LCollectionValue);
      end;
    finally
      if LCreated then
        LCollection.Free;
    end;
  end;
end;

end.

