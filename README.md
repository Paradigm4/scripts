scripts
=======

## Miscellaneous SciDB scripts and utilities

### scidb_backup.sh

This is a basic script that backs up SciDB databases to files and reloads them.
The script helps automate some of the details by saving all arrays listed in
the database along with a manifest of the saved arrays and their schema.

It can save arrays in SciDB's 'opaque' storage format, or in binary format
based on the array attribute types as a fallback if the opaque storage format
won't work (for example across incompatible SciDB versions). Beware that the
binary storage format only saves the current version of the listed arrays.

Examples follow:

* Back up all data to one directory named 'backupdir' on the SciDB coordinator instance
using the SciDB 'opaque' storage format:

    ```
    scidb_backup save-opaque backupdir
    ```

* ...and the reload the data...

    ```
    scidb_backup restore-opaque backupdir
    ```

* Back up all data to one directory named 'backupdir' on the SciDB coordinator instance
using binary storage formats based on array attributes (also showing reload):

    ```
    scidb_backup save-binary backupdir
    scidb_backup restore-binary backupdir
    ```

* Back up and restore all data in parallel to one subdirectory per SciDB instance, located inside each instance data directory, using the SciDB 'opaque' storage format:

    ```
    scidb_backup save-opaque backupdir 1
    scidb_backup restore-opaque backupdir 1
    ```
