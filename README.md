scripts
=======

## man2scidb

Use the man2scidb script  to build a SciDB array that contains the
SciDB source code Doxygen help for SciDB operators. This script requires
that you have the SciDB source code, available from http://www.paradigm4.com

### Step 1

Edit doc/api/Doxyfile.in in your SciDB source trunk directory.  Change the following line from:
```
GENERATE_MAN           = NO
```
to:
```
GENERATE_MAN           = YES
```
Then build SciDB normally, for example using the run.py script.

### Step 2

In the staging directory where SciDB was built you will have a directory like:
```
stage/build/doc/api/man/man3/
```
If you **don't** have this directory, navigate to:
```
stage/build/doc/api
```
and run:
```
doxygen Doxyfile
```

### Step 3

Make sure SciDB is running and navigate to the stage/build/doc/api/man/man3 directory and run the man2scidb script.

Voila! You now have an array named 'help' that has all our operator Doxygen documentation in it. You can directly filter this file for specific operators, or
feel free to use index_lookup and redimension to dimension along operator name.

### Example
```
iquery -aq "filter(help, name='rehsape')"
{i} name,help
{57} 'reshape','
scidb::LogicalReshape(3)			      scidb::LogicalReshape(3)



NAME
       scidb::LogicalReshape -

       The operator: reshape().


SYNOPSIS
       Inherits scidb::LogicalOperator.

   Public Member Functions
       LogicalReshape (const string &logicalName, const std::string &alias)
       ArrayDesc inferSchema (std::vector< ArrayDesc > schemas,
	   boost::shared_ptr< Query > query)

Detailed Description
       The operator: reshape().
       Synopsis:.RS 4 reshape( srcArray, schema )

Summary:.RS 4 Produces a result array containing the same cells as, but a
different shape from, the source array.

Input:.RS 4


· srcArray: the source array with srcAttrs and srcDims.

· schema: the desired schema, with the same attributes as srcAttrs, but with
  different size and/or number of dimensions. The restriction is that the
  product of the dimension sizes is equal to the number of cells in srcArray.


Output array:.RS 4 <
 srcAttrs
 >
 [
 dimensions from the provided schema
 ]

Examples:.RS 4 n/a

Errors:.RS 4 n/a

Notes:.RS 4 n/a




Author
       Generated automatically by Doxygen for SciDB from the source code.



SciDB				  17 Mar 2014	      scidb::LogicalReshape(3)
```


## scidb_backup.sh
### NOTE: The scidb_backup script has been promoted to official status and is included with SciDB as of version 14.3. We'll keep this software archive but it's no longer actively maintained.


Easily back up or restore arrays in a SciDB database.

#### Synopsis

```
scidb_backup.sh <command> [--parallel] [--allVersions] [--pattern PTRN] [-z] <directory>
```

```<command>``` is one of ```--save-opaque```, ```--restore-opaque```, ```--save-binary```, ```--restore-binary```, ```--save-text```, ```--restore-text```.

```<directory>``` is the name of a directory to save data to, see the discussion below.

The optional --parallel flag enables parallel save/load. Otherwise save and load
all the data to one directory on the SciDB coordinator instance.

Optional --allVersions flag directs the utility to save all versions of arrays
in scidb.

Optional --pattern flag forces the utility to filter array names based on the
specified PTRN value.  PTRN value is a grep-like pattern used by the utility 
to find matching array names.

Optional -z flag compresses/decompresses array data files with gzip.  If the 
backup was saved with -z flag, then the same flag has to be specified during 
the restore operation.

#### Details
This is a basic script that backs up SciDB databases to files and reloads them.
The script helps automate some of the details by saving all arrays listed in
the database along with a manifest of the saved arrays and their schema.

It can save arrays in SciDB's 'opaque' storage format, or in binary format
based on the array attribute types as a fallback if the opaque storage format
won't work (for example across incompatible SciDB versions).

### Caution

* Opaque format should almost never be used to back up data between SciDB
  database versions. Use binary format instead. (Use opaque format to
  quickly back up and restore data within a single SciDB version, for example
  to help with node recovery.)
* Parallel restore must run on a SciDB cluster of the same size that parallel save ran on.

### Examples

* Back up all data into one directory named 'backupdir' on the SciDB coordinator instance
using the SciDB 'opaque' storage format:

    ```
    scidb_backup --save-opaque backupdir
    ```

* ...and the reload the data...

    ```
    scidb_backup --restore-opaque backupdir
    ```

* Back up all data into one directory named 'backupdir' on the SciDB coordinator instance
using binary storage formats based on array attributes (also showing reload):

    ```
    scidb_backup --save-binary backupdir
    scidb_backup --restore-binary backupdir
    ```

* Back up and restore all data in parallel in one subdirectory per SciDB instance. The subdirectories will be located in this example in /tmp/backup.**j** created across the nodes, where **j** is a number corresponding to each SciDB instance. The directories will be created by ssh commands issued to each SciDB instance node. This example uses the `binary` format:

    ```
    scidb_backup --save-binary /tmp/backup --parallel
    scidb_backup --restore-binary /tmp/backup --parallel
    ```
 * Back up and restore all arrays starting with letter A in parallel:

    ```
    scidb_backup --save-binary /tmp/backup --parallel --pattern "A.*"
    scidb_backup --restore-binary /tmp/backup --parallel
    ```
 * Back up and restore all versions of arrays starting with letter A in parallel.  In this case, the backup folder will contain files A*@1, A*@2, etc.  The array data files will be matching the pattern A* and will also have version specifiers (1,2,3,...):

    ```
    scidb_backup --save-binary /tmp/backup --parallel --allVersions --pattern "A.*"
    scidb_backup --restore-binary /tmp/backup --parallel
    ```
