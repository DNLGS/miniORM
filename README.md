# MiniORM

Estudo de ORM em Delphi com Firebird e IBX. Faz mapeamento por atributos, CRUD, consultas e relacionamentos HasMany.

Criado por mim, com revisao auxiliada por IA.

## Como usar

Adicione `src` ao Search Path do projeto. Configure e conecte um `TIBDatabase`. As tabelas devem existir no banco; o ORM nao cria o schema.

Exemplo de entidade para uma tabela `PESSOA`, com `ID` gerado pelo banco:

```delphi
uses miniOrm.Attributes, miniOrm.DbObjectBase;

type
  [Table('PESSOA')]
  TPessoa = class(TDbObjectBase)
  private
    FId: Integer;
    FNome: string;
  published
    [Column('ID'), PK, AutoIncrement]
    property Id: Integer read FId write FId;

    [Column('NOME'), NotNull]
    property Nome: string read FNome write FNome;
  end;
```

Use o contexto para gravar e consultar:

```delphi
uses miniOrm.Context;

var
  Orm: TOrmContext;
  Pessoa: TPessoa;
begin
  Orm := TOrmContext.Create(IBDatabase1);
  try
    Pessoa := TPessoa.Create;
    try
      Pessoa.Nome := 'Maria';
      Orm.BeginTransaction;
      try
        Orm.Inserir<TPessoa>(Pessoa);
        // Orm.Update<TPessoa>(Pessoa);
        // Orm.Delete<TPessoa>(Pessoa);
        Orm.Commit;
      except
        Orm.Rollback;
        raise;
      end;
    finally
      Pessoa.Free;
    end;

    Pessoa := (Orm.Select<TPessoa>().Where('Nome') = 'Maria').FirstOrDefault;
    try
      if Pessoa <> nil then
        ShowMessage(Pessoa.Nome);
    finally
      Pessoa.Free;
    end;
  finally
    Orm.Free;
  end;
end;
```

Gravacoes usam transacao manual. SELECTs usam uma transacao interna, encerrada ao liberar o contexto. O snapshot da leitura permanece o mesmo durante esse periodo. Para listas, use `ToList`, consuma antes de liberar o contexto e libere a colecao com `Free`.

Projeto de estudo, sem garantia de uso em producao.
