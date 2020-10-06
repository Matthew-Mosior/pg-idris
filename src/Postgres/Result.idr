module Postgres.Result

import Postgres.Utility

||| Internal phantom type used to mark pointers to the
||| `libpq` struct of the same name.
export 
data PGresult : Type

%foreign libpq "PQclear"
prim__dbClearResult : Ptr PGresult -> PrimIO ()

||| The result of executing a command. See `Postgres.Exec`
||| for more.
export
data Result : Type where
  MkResult : Ptr PGresult -> Result

||| All of the various forms of execution supported by libpq
||| provide types that conform to the `ResultProducer` interface.
public export
interface ResultProducer source input where
  exec : source -> input -> IO (Ptr PGresult)

||| Execute the given result producer, do the given thing with the
||| result, and then free the memory used for the result.
export
withResult : ResultProducer source a => source -> a -> (Result -> IO b) -> IO b
withResult src cmd f = do resPtr <- exec src cmd
                          out <- f $ MkResult resPtr
                          primIO $ prim__dbClearResult resPtr
                          pure out



--
-- Result Status
--

||| See the `ExecStatusType` from libpq for more information.
||| constructors below are derived from libpq options by
||| dropping the "PGRES_" prefix
public export 
data ResultStatus = EMPTY_QUERY
                  | COMMAND_OK
                  | TUPLES_OK
                  | COPY_OUT
                  | COPY_IN
                  | BAD_RESPONSE
                  | NONFATAL_ERROR
                  | FATAL_ERROR
                  | COPY_BOTH
                  | SINGLE_TUPLE
                  | OTHER Int

resultStatus : Int -> ResultStatus
resultStatus i =
  case i of
       0 => EMPTY_QUERY
       1 => COMMAND_OK
       2 => TUPLES_OK
       3 => COPY_OUT
       4 => COPY_IN
       5 => BAD_RESPONSE
       6 => NONFATAL_ERROR
       7 => FATAL_ERROR
       8 => COPY_BOTH
       9 => SINGLE_TUPLE
       x => OTHER x

export
Show ResultStatus where
  show EMPTY_QUERY    = "EMPTY_QUERY"
  show COMMAND_OK     = "COMMAND_OK"
  show TUPLES_OK      = "TUPLES_OK"
  show COPY_OUT       = "COPY_OUT"
  show COPY_IN        = "COPY_IN"
  show BAD_RESPONSE   = "BAD_RESPONSE"
  show NONFATAL_ERROR = "NONFATAL_ERROR"
  show FATAL_ERROR    = "FATAL_ERROR"
  show COPY_BOTH      = "COPY_BOTH"
  show SINGLE_TUPLE   = "SINGLE_TUPLE"
  show (OTHER x)      = "OTHER " ++ (show x)

%foreign libpq "PQresultStatus"
prim__dbResultStatus : Ptr PGresult -> Int

export
pgResultStatus : Result -> ResultStatus
pgResultStatus (MkResult res) = resultStatus $ prim__dbResultStatus res

export
pgResultSuccess : Result -> Bool
pgResultSuccess res with (pgResultStatus res)
  pgResultSuccess res | EMPTY_QUERY = True
  pgResultSuccess res | COMMAND_OK = True
  pgResultSuccess res | TUPLES_OK = True
  pgResultSuccess res | COPY_OUT = True
  pgResultSuccess res | COPY_IN = True
  pgResultSuccess res | COPY_BOTH = True
  pgResultSuccess res | SINGLE_TUPLE = True
  pgResultSuccess res | x = False

--
-- Result Value
--

%foreign libpq "PQntuples"
prim__dbResultRowCount : Ptr PGresult -> Int

%foreign libpq "PQnfields"
prim__dbResultColCount : Ptr PGresult -> Int

||| Get the size of the resultset as (row, col).
export 
pgResultSize : Result -> (Nat, Nat)
pgResultSize (MkResult res) = 
  (
    integerToNat $ cast $ prim__dbResultRowCount res,
    integerToNat $ cast $ prim__dbResultColCount res
  )

%foreign libpq "PQgetvalue"
prim__dbResultValue : Ptr PGresult -> (row: Int) -> (col: Int) -> String

export
dbResultValue : Result -> (row: Nat) -> (col: Nat) -> String
dbResultValue (MkResult res) row col = prim__dbResultValue res (cast row) (cast col)

