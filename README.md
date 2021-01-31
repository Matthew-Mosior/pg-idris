# pg-idris

The beginnings of a Postgres library for Idris 2.

Early days with no real plans for completion, but you might still find something here informative.

This project is going to see tons of breaking changes as I experiment with approaches to support Postgres from an Idris interface.

## Status

Currently supports:
- Connecting to database.
- Arbitrary string commands with the result status returned.
- Arbitrary string queries with response parsed as JSON.
- Arbitrary string queries with result columns all interpreted as Strings.
- Listen for notifications on a particular channel.
- Request next unprocessed notification.

## Dependencies

This library currently depends on bleeding edge of the Idris 2 project. As of this writing, I believe the library will build against Idris 2 v0.3.0, but at any time in the future you might need to build and install Idris 2 from its `master` branch in order to build and use this library.

You also need `libpq` (the Postgres C client implementation) installed.

## Usage

You can take a look at the `Main.idr` and `example.ipkg` in the Example folder for an example of using the library. 

### Install the library
Run the `make install` to build and install the library (including a workaround I found I needed on OS X that copies the library output to a `.dylib`).

### Include the package
When running `idris2`, pass the package in with the `-p pg-idris` and `-p contrib` command line arguments.

If you have a package manifest, add `pg-idris` and `contrib` to the list of `depends`:
```
package yourpackage

...

depends = contrib, pg-idris
```

### High level usage
There are some lower level functions available, but the high level usage is currently as follows.

#### Establish a connection
First, `import Postgres`.

You can use the `Database` type to open a connection, work with it, and then close it again.
```idris
openAndClose : (url : String) -> Database () Closed (const Closed)
openAndClose url =
  do initDatabase
     OK <- openDatabase url
       | Failed err => pure () -- connection error!
     ?databaseRoutine
     closeDatabase
```

The type of the hole `?databaseRoutine` is `Database ?a Open (\x => Open)`; in other words, you can do anything there that operates on an open database connection and does not close it.

You'll need to run your `Database` through `evalDatabase` to produce IO.

Opening and closing and producing IO are a bit boring, so you can use `withDB` to hide those details and focus on `?databaseRoutine`:
```idris
runRoutine : HasIO io => (url : String) -> io (Either String ())
runRoutine url =
  withDB url ?databaseRoutine
```

#### Write a routine
For now, there's not much you'll want to do inside your routine other than prepare and execute a command:
```idris
execCommand : Database () Open (const Open)
execCommand = do liftIO $ putStrLn "Woo! Running a command!"
                 exec ?postgresCommand
```

The type of the hole `?postgresCommand` is `Connection -> IO ()`. In other words, anything you might want to do given an open Postgres connection.

#### Run commands
The following commands are currently available.
```idris
||| Query the database interpreting all columns as strings.
stringQuery : (header : Bool) -> (query : String) -> Connection -> IO (Either String (StringResultset header))

||| Query the database expecting a JSON result is returned.
jsonQuery : (query : String) -> Connection -> IO (Maybe JSON)

||| Start listening for notifications on the given channel.
listen : (channel : String) -> Connection -> IO ResultStatus

perform : (command : String) -> Connection -> IO ResultStatus

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
nextNotification : Connection -> IO (Maybe Notification)
```

It's worth mentioning that the `stringQuery` success case can either have a header (with column names) or not:
```idris
StringResultset : (header : Bool) -> Type
StringResultset False = (rows ** cols ** Vect rows (Vect cols String))
StringResultset True = (rows ** cols ** (Vect cols String, Vect rows (Vect cols String)))
```

Notice that other than JSON responses, all responses are currently string-typed requiring extra work to attempt to parse them into expected value types. Getting better types out of this library is the current area of development.

