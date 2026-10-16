unit miniOrm.EntityMetadataCache;

interface

uses
  miniOrm.Types,
  Generics.Collections,
  SysUtils,
  SyncObjs;

type
  TEntityMetadataCache = class
  private
    class var FEntities: TObjectDictionary<TClass, TEntityMetadata>;
    class var FLock: TCriticalSection;
    class constructor Create;
    class destructor Destroy;
  public
    class function GetOrCreateEntity(AClass: TClass): TEntityMetadata; static;
  end;

implementation

class constructor TEntityMetadataCache.Create;
begin
  FLock := TCriticalSection.Create;
  try
    FEntities := TObjectDictionary<TClass, TEntityMetadata>.Create([doOwnsValues]);
  except
    FLock.Free;
    FLock := nil;
    raise;
  end;
end;

class destructor TEntityMetadataCache.Destroy;
begin
  FEntities.Free;
  FLock.Free;
end;

class function TEntityMetadataCache.GetOrCreateEntity(
  AClass: TClass): TEntityMetadata;
begin
  if AClass = nil then
    raise EArgumentNilException.Create('A classe da entidade não pode ser nil.');

  FLock.Enter;
  try
    if not FEntities.TryGetValue(AClass, Result) then
    begin
      Result := TEntityMetadata.Create(AClass);
      try
        FEntities.Add(AClass, Result);
      except
        Result.Free;
        raise;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

end.
