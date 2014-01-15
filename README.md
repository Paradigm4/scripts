scripts
=======

## Miscellaneous SciDB scripts and utilities

### scidb_backup.sh

Easily back up or restore all arrays in a SciDB database.

#### Synopsis

```
scidb_backup.sh <command> <directory> [parallel]
```

```<command>``` is one of ```save-opaque```, ```restore-opaque```, ```save-binary```, ```restore-binary```.

```<directory>``` is the name of a directory to save data to, see the discussion below.

The optional parallel flag enables parallel save/load. Otherwise save and load
all the data to one directory on the SciDB coordinator instance.

#### Details
This is a basic script that backs up SciDB databases to files and reloads them.
The script helps automate some of the details by saving all arrays listed in
the database along with a manifest of the saved arrays and their schema.

It can save arrays in SciDB's 'opaque' storage format, or in binary format
based on the array attribute types as a fallback if the opaque storage format
won't work (for example across incompatible SciDB versions).

### Caution

* Beware that both formats only saves the last version of the listed arrays.
* Opaque format should almost never be used to back up data between SciDB
  database versions. Use binary format instead. (Use opaque format to
  quickly back up and restore data within a single SciDB version, for example
  to help with node recovery.)
* Parallel restore must run on a SciDB cluster of the same size that parallel save ran on.

### Examples

* Back up all data into one directory named 'backupdir' on the SciDB coordinator instance
using the SciDB 'opaque' storage format:

    ```
    scidb_backup save-opaque backupdir
    ```

* ...and the reload the data...

    ```
    scidb_backup restore-opaque backupdir
    ```

* Back up all data into one directory named 'backupdir' on the SciDB coordinator instance
using binary storage formats based on array attributes (also showing reload):

    ```
    scidb_backup save-binary backupdir
    scidb_backup restore-binary backupdir
    ```

* Back up and restore all data in parallel in one subdirectory per SciDB instance. The subdirectories will be located in this example in /tmp/backup.**j** created across the nodes, where **j** is a number corresponding to each SciDB instance. The directories will be created by ssh commands issued to each SciDB instance node. This example uses the `binary` format:

    ```
    scidb_backup save-binary /tmp/backup parallel
    scidb_backup restore-binary /tmp/backup parallel
    ```
