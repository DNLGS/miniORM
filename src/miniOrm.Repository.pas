unit miniOrm.Repository;

interface

uses  miniOrm.DatabaseConnection.Intf,
  miniOrm.Types, miniOrm.DbObjectBase, miniOrm.Repository.Intf,
  miniOrm.EntitySQLService, miniOrm.QueryBuilder, SysUtils;

type
  TRepository<T: TDbObjectBase, constructor> = class(TInterfacedObject, IObjectRepository<T>)
  private
    FDatabaseConnection : IDatabaseConnection;
  public
    function Select : IQueryBuilder<T>;
    procedure Inserir(const AObject: T);
    procedure Update(const AObject: T);
    procedure Delete(const AObject: T);
    constructor Create(ADatabaseConnection : IDatabaseConnection);
  end;

implementation

{ TRepository<T> }

constructor TRepository<T>.Create(
  ADatabaseConnection: IDatabaseConnection);
begin
  FDatabaseConnection := ADatabaseConnection;
end;

procedure TRepository<T>.Delete(const AObject: T);
begin
  if FDatabaseConnection.Execute(
    TEntitySQLService.GetDeleteSQL(AObject.Metadata),
    TEntitySQLService.GetValues(dbDelete, AObject, AObject.Metadata)) <> 1 then
    raise EInvalidOpException.Create('A operacao deve afetar exatamente um registro.');
end;

procedure TRepository<T>.Inserir(const AObject: T);
var
  LValues: TValues;
begin
  LValues := FDatabaseConnection.ExecuteWithReturn(
    TEntitySQLService.GetInsertSQL(AObject.Metadata),
    TEntitySQLService.GetValues(dbInsert, AObject, AObject.Metadata));

  try
    TEntitySQLService.ApplyUpdates(AObject, AObject.Metadata, LValues);
  finally
    LValues.Free;
  end;
end;

function TRepository<T>.Select: IQueryBuilder<T>;
begin
  Result := TQueryBuilder<T>.New(FDatabaseConnection);
end;

procedure TRepository<T>.Update(const AObject: T);
begin
  if FDatabaseConnection.Execute(
    TEntitySQLService.GetUpdateSQL(AObject.Metadata),
    TEntitySQLService.GetValues(dbUpdate, AObject, AObject.Metadata)) <> 1 then
    raise EInvalidOpException.Create('A operacao deve afetar exatamente um registro.');
end;

end.
