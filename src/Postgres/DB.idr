module Postgres.DB

import public Postgres.Data.ResultStatus
import public Postgres.Result
import public Postgres.Query

import Postgres.DB.Core
import Postgres.Data.Conn
import Postgres.Data.ConnectionStatus
import Postgres.Data.PostgresType
import Postgres.Data.PostgresValue
import Postgres.Exec
import Postgres.LoadTypes
import Postgres.Notification
import Language.JSON
import Data.HVect
import Data.Vect.Quantifiers

--
-- Safe connection
--

||| Open a connection to a Postgres database,
||| perform some actions with it, and then close
||| the connection.
|||
||| If the database connection is established successfully,
||| the `onOpen` function will be executed. If the
||| connection cannot be established, `onError` will be
||| executed.
|||
||| You do _not_ call `pgOpen` or `pgClose` directly
||| when using this function.
export
withConn : HasIO io => (pgUrl: String) -> (onOpen: Conn -> io b) -> (onError: ConnectionStatus -> io b) -> io b
withConn pgUrl onOpen onError 
  = do conn <- pgOpen pgUrl
       out <- case (pgStatus conn) of
                OK => onOpen conn
                x => onError x
       pgClose conn
       pure out

--
-- Database abstraction
--

public export
data DBState = Open | Closed

public export 
data OpenResult = OK | Failed String

public export
OpenResultState : OpenResult -> DBState
OpenResultState = \case OK         => Open
                        (Failed _) => Closed

openResult : Conn -> OpenResult
openResult conn = case (pgStatus conn) of
                       OK => OK
                       x  => Failed (show x)

export
data Connection : Type where
  MkConnection : Conn -> TypeDictionary -> Connection

getConn : Connection -> Conn
getConn (MkConnection conn _) = conn

getTypes : Connection -> TypeDictionary
getTypes (MkConnection _ types) = types

export
data Database : (ty : Type) -> (s1 : DBState) -> (s2Fn : (ty -> DBState)) -> Type where
  DBOpen  : (url : String) -> Database OpenResult Closed OpenResultState
  DBClose : Database () Open (const Closed)

  Exec    : (fn : Connection -> IO a) -> Database a Open (const Open)

  DIO      : IO a -> Database a s1 (const s1)

  GetTypes : Database TypeDictionary Open (const Open)

  Pure    : (x : a) -> Database a (stateFn x) stateFn
  Bind    : (db : Database a s1 s2Fn) -> (f : (x : a) -> Database b (s2Fn x) s3Fn) -> Database b s1 s3Fn

%name Database db, db1, db2

export
(>>=) : (db : Database a s1 s2Fn) -> (f : (x : a) -> Database b (s2Fn x) s3Fn) -> Database b s1 s3Fn
(>>=) = Bind

export
(>>) : (db : Database a s1 (const s2)) -> Database b s2 s3Fn -> Database b s1 s3Fn
db >> db2 = db >>= (\_ => db2)


export
pure : (x : a) -> Database a (stateFn x) stateFn
pure = Pure

export
liftIO' : IO a -> Database a s1 (const s1)
liftIO' = DIO

data ConnectionState : DBState -> Type where
  CConnected : (conn : Connection) -> ConnectionState Open
  CDisconnected : ConnectionState Closed

runDatabase' : HasIO io => ConnectionState s1 -> Database a s1 s2Fn -> io $ (x : a ** ConnectionState (s2Fn x))
runDatabase' CDisconnected (DBOpen url) = do conn <- pgOpen url
                                             Right types <- pgLoadTypes conn
                                               | Left err => pure (Failed err ** CDisconnected)
                                             pure $ case openResult conn of
                                                         OK => (OK ** CConnected (MkConnection conn types))
                                                         Failed err => (Failed err ** CDisconnected)
runDatabase' (CConnected conn) DBClose = do pgClose (getConn conn)
                                            pure $ (() ** CDisconnected)
runDatabase' (CConnected conn) (Exec fn) = liftIO $ do res <- fn conn
                                                       pure (res ** CConnected conn)
runDatabase' (CConnected conn) GetTypes = pure $ (getTypes conn ** CConnected conn)
runDatabase' cs (Pure y) = pure (y ** cs)
runDatabase' cs (Bind db f) = do (res ** cs') <- runDatabase' cs db
                                 runDatabase' cs' (f res)
runDatabase' cs (DIO io) = do v <- liftIO io
                              pure (v ** cs)

export
evalDatabase : HasIO io => Database a Closed (const Closed) -> io a
evalDatabase db = pure $ fst !(runDatabase' CDisconnected db)

export
initDatabase : Database () Closed (const Closed)
initDatabase = pure ()

export
openDatabase : (url : String) -> Database OpenResult Closed OpenResultState
openDatabase = DBOpen

export
closeDatabase : Database () Open (const Closed)
closeDatabase = DBClose

export
exec : (Connection -> IO a) -> Database a Open (const Open)
exec = Exec

||| You can execute arbitrary things against the lower-level
||| Conn, including closing the database connection prematurely.
export
unsafeExec : (Conn -> IO a) -> Database a Open (const Open)
unsafeExec f = Exec \(MkConnection conn empty) => f conn

||| Take a function that operates on a Conn
||| (currency of the underlying lower level
||| Postgres stuff) and turn it into a function
||| that operates on a Connection.
pgExec : (Conn -> IO a) -> Connection -> IO a
pgExec f = f . getConn 

export
withDB : HasIO io => (url : String) -> Database a Open (const Open) -> io $ Either String a
withDB url dbOps = evalDatabase dbCommands
  where
    dbCommands : Database (Either String a) Closed (const Closed)
    dbCommands = do initDatabase
                    OK <- openDatabase url
                      | Failed err => pure $ Left err
                    out <- dbOps
                    closeDatabase
                    pure $ Right out

||| Dump the Postgres type dictionary for debugging purposes.
export
debugDumpTypes : Database () Open (const Open)
debugDumpTypes = do types <- GetTypes
                    liftIO' $ putStrLn $ show types
                    pure ()

--
-- Postgres Commands
--

||| Query the database interpreting all columns as strings.
export
stringQuery : (header : Bool) -> (query : String) -> Connection -> IO (Either String (StringResultset header))
stringQuery header query (MkConnection conn types) = pgStringResultsQuery header query conn

||| Query the database expecting a JSON result is returned.
export 
jsonQuery : (query : String) -> Connection -> IO (Maybe JSON)
jsonQuery = pgExec . pgJSONResultQuery

||| Query the database expecting the given array of types in each
||| row of the result returned.
export
expectedQuery : {cols : Nat} 
             -> (expected : Vect cols Type) 
             -> (query : String) 
             -> {auto castable : (All Castable expected)} 
             -> Connection 
             -> IO (Either String (rows ** Vect rows (HVect expected)))
expectedQuery expected query (MkConnection conn types) = pgResultQuery expected query conn

||| Perform the given command and instead of parsing the response
||| just report the result status. This is useful when you don't
||| care if/what the response looks like, just whether the command
||| worked
export
perform : (command : String) -> Connection -> IO ResultStatus
perform cmd = pgExec (\c => withExecResult c cmd (pure . pgResultStatus))

||| Start listening for notifications on the given channel.
export
listen : (channel : String) -> Connection -> IO ResultStatus
listen = pgExec . pgListen

||| Gets the next notification _of those sitting around locally_.
||| Returns `Nothing` if there are no notifications.
|||
||| See `libpq` documentation on `PQnotifies` for details on the
||| distinction between retrieving notifications from the server and
||| getting the next notification that has already been retrieved.
|||
||| NOTE: This function _does_ consume input to make sure no notification
|||  sent by the server but not processed by the client yet gets
|||  missed.
export
nextNotification : Connection -> IO (Maybe Notification)
nextNotification = pgExec pgNextNotification

||| Produce a potentially infinite stream of notifications.
||| Unlike `nextNotificaiton`, this will wait for the server
||| to deliver a notification.
|||
||| This _is_ an infinite sequence with a blocking wait for the
||| next notification so it is of somewhat limited utility
||| compared to checking for new notifications at a natural point
||| in your programs existing logic loop unless your entire loop
||| is dictated by notification arrival anyway.
export
partial
notificationStream : Connection -> Stream (IO Notification)
notificationStream = pgNotificationStream . getConn

