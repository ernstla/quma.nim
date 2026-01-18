type
  QumaError* = object of CatchableError

  ScriptNotFoundError* = object of QumaError

  QueryError* = object of QumaError
  QueryNoRowsError* = object of QueryError
  QueryTooManyRowsError* = object of QueryError

  TemplateError* = object of QumaError
