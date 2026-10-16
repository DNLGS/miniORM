unit miniOrm.DatabaseConnection.Intf;

interface

uses miniOrm.Types, Generics.Collections;

type
  IDatabaseConnection = interface
    ['{58792539-394A-4F56-A91D-53DE549D06FA}']

    procedure BeginTransaction(AIsolation: TTransactionIsolation = tiSnapshot);
    procedure Commit;
    procedure Rollback;
    function Execute(const ASQL : String; const AParams: TParams): Int64;
    function ExecuteWithReturn(const ASQL : String; const AParams: TParams): TValues;
    function Query(const ASQL: string; const AParams: TParams;
      AMaxRows: Integer = 0): TObjectList<TValues>;
    function OpenReadSession: IDatabaseConnection;
    function InTransaction : Boolean;
    function TransactionIsolation: TTransactionIsolation;
    function TransactionVersion: Int64;
  end;

implementation

end.
