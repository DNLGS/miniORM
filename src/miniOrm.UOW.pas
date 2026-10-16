unit miniOrm.UOW;

interface

uses miniOrm.DatabaseConnection.Intf, miniOrm.Types;

type
  TUOW = class
  private
    FIDatabaseConnection : IDatabaseConnection;
  public
    constructor Create(const IDatabaseConnection : IDatabaseConnection);
    procedure BeginTransaction(AIsolation: TTransactionIsolation = tiSnapshot);
    procedure Commit;
    procedure Rollback;
  end;

implementation

{ TUOW }

procedure TUOW.BeginTransaction(AIsolation: TTransactionIsolation);
begin
  FIDatabaseConnection.BeginTransaction(AIsolation);
end;

procedure TUOW.Commit;
begin
  FIDatabaseConnection.Commit;
end;

constructor TUOW.Create(const IDatabaseConnection: IDatabaseConnection);
begin
  FIDatabaseConnection := IDatabaseConnection;
end;

procedure TUOW.Rollback;
begin
  FIDatabaseConnection.Rollback;
end;

end.
