unit miniOrm.Attributes;

interface

type
  Column = class(TCustomAttribute)
  private
    FName : String;
  public
    constructor Create(const AName : String);
    property Name: String read FName;
  end;

  Table = class(TCustomAttribute)
  private
    FName : String;
  public
    constructor Create(const AName : String);
    property Name: String read FName;
  end;

  PK = class(TCustomAttribute)
  end;

  Ignore = class(TCustomAttribute)
  end;

  NotNull = class(TCustomAttribute)
  end;

  AutoIncrement = class(TCustomAttribute)
  end;

  MaxLength = class(TCustomAttribute)
  private
    FValue : Integer;
    FRaiseEx : Boolean;
  public
    constructor Create(const AValue : Integer; ARaiseEx : Boolean = False);
    property Value: Integer read FValue;
    property RaiseEx: Boolean read FRaiseEx;
  end;

  DefaultValue = class(TCustomAttribute)
  private
    FValue : Variant;
  public
    constructor Create(const AValue : Variant);
    property Value: Variant read FValue;
  end;

  HasMany = class(TCustomAttribute)
  private
    FParentProperty: string;
    FChildProperty: string;
  public
    constructor Create(
      const AParentProperty, AChildProperty: string);

    property ParentProperty: string read FParentProperty;
    property ChildProperty: string read FChildProperty;
  end;

implementation

uses SysUtils;

{ Field }

constructor Column.Create(const AName: String);
begin
  inherited Create;
  FName := AName;
end;

{ Table }

constructor Table.Create(const AName: String);
begin
  inherited Create;
  FName := AName;
end;

{ MaxLength }

constructor MaxLength.Create(const AValue: Integer; ARaiseEx : Boolean);
begin
  inherited Create;
  if AValue <= 0 then
    raise EArgumentOutOfRangeException.Create('MaxLength deve ser positivo.');
  FRaiseEx := ARaiseEx;
  FValue := AValue;
end;

{ DefaultValue }

constructor DefaultValue.Create(const AValue: Variant);
begin
  inherited Create;
  FValue := AValue;
end;

{ HasMany }

constructor HasMany.Create(const AParentProperty, AChildProperty: string);
begin
  inherited Create;
  FParentProperty := AParentProperty;
  FChildProperty := AChildProperty;
end;

end.
