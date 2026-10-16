unit miniOrm.Repository.Intf;

interface

uses Variants, SysUtils, miniOrm.DatabaseConnection.Intf, miniOrm.DbObjectBase,
  miniOrm.QueryBuilder;

type
  IObjectRepository<T: TDbObjectBase, constructor> = interface
    ['{66DA37C4-4E21-4760-9D0F-9440E72A05AD}']
    function Select : IQueryBuilder<T>;
    procedure Inserir(const AObject: T);
    procedure Update(const AObject: T);
    procedure Delete(const AObject: T);
  end;

implementation

end.
