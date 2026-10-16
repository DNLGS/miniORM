unit miniOrm.Context;

interface

uses
  SysUtils, IBX.IBDatabase,
  miniOrm.Types, miniOrm.DatabaseConnection.Intf, miniOrm.DbObjectBase,
  miniOrm.Repository.Intf, miniOrm.QueryBuilder;

type
  TOrmContext = class
  private
    FConnection: IDatabaseConnection;
    FReadConnection: IDatabaseConnection;
  public
    constructor Create(const ADatabase: TIBDatabase); overload;
    constructor Create(const AConnection: IDatabaseConnection); overload;
    destructor Destroy; override;
    function Repository<T: TDbObjectBase, constructor>: IObjectRepository<T>;
    function Select<T: TDbObjectBase, constructor>: IQueryBuilder<T>;
    procedure Inserir<T: TDbObjectBase, constructor>(const AObject: T);
    procedure Update<T: TDbObjectBase, constructor>(const AObject: T);
    procedure Delete<T: TDbObjectBase, constructor>(const AObject: T);
    procedure BeginTransaction(AIsolation: TTransactionIsolation = tiSnapshot);
    procedure Commit;
    procedure Rollback;
  end;

implementation

uses
  miniOrm.IBXConnection, miniOrm.Repository;

constructor TOrmContext.Create(const ADatabase: TIBDatabase);
begin
  inherited Create;
  FConnection := TIBXDatabaseConnection.Create(ADatabase);
end;

constructor TOrmContext.Create(const AConnection: IDatabaseConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Informe a conexao do ORM.');
  FConnection := AConnection;
end;

destructor TOrmContext.Destroy;
begin
  try
    if (FReadConnection <> nil) and FReadConnection.InTransaction then
      FReadConnection.Rollback;
  finally
    FReadConnection := nil;
    inherited Destroy;
  end;
end;

function TOrmContext.Repository<T>: IObjectRepository<T>;
begin
  Result := TRepository<T>.Create(FConnection);
end;

function TOrmContext.Select<T>: IQueryBuilder<T>;
begin
  if FReadConnection = nil then
    FReadConnection := FConnection.OpenReadSession;
  Assert(FReadConnection <> FConnection,
    'A leitura deve ter uma transacao independente da gravacao.');
  Result := TQueryBuilder<T>.New(FReadConnection);
end;

procedure TOrmContext.Inserir<T>(const AObject: T);
begin
  if AObject = nil then
    raise EArgumentNilException.Create('Informe o objeto para inserir.');
  Repository<T>().Inserir(AObject);
end;

procedure TOrmContext.Update<T>(const AObject: T);
begin
  if AObject = nil then
    raise EArgumentNilException.Create('Informe o objeto para atualizar.');
  Repository<T>().Update(AObject);
end;

procedure TOrmContext.Delete<T>(const AObject: T);
begin
  if AObject = nil then
    raise EArgumentNilException.Create('Informe o objeto para excluir.');
  Repository<T>().Delete(AObject);
end;

procedure TOrmContext.BeginTransaction(AIsolation: TTransactionIsolation);
begin
  FConnection.BeginTransaction(AIsolation);
end;

procedure TOrmContext.Commit;
begin
  FConnection.Commit;
end;

procedure TOrmContext.Rollback;
begin
  FConnection.Rollback;
end;

end.
