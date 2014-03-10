     _______ _______ _______
    |    ___|   |   |   _   |
    |    ___|       |       |
    |_______|__|_|__|___|___|

**ema** -- Simple process manager for node.js app.

# synopsis

    ema [-hVtqd] [-s signal] [-p dirname] [-c filename] [-g directives]

# options

    -h, --help                    output usage information
    -V, --version                 output the version number
    -t, --test                    test configuration and exit
    -q, --quiet                   suppress non-error messages during configuration testing
    -d, --daemon                  daemonize process
    -s, --signal <signal>         send signal to a master process: stop, quit, reload
    -p, --prefix <dirname>        set prefix path
    -c, --config <filename>       set configuration json file
    -g, --directives <directive>  set master directives out of configuration file

### -h, help

  Print help.

### -V, version

  Print the **ema** version.

### -t, test

  Do not run, just test the configuration file.

  **ema** checks the configuration file syntax.

### -q, --quiet

  Supress non-error messages during configuration testing.

### -d, --daemon

  Respawn the process as a daemon.

  The parent process will exit at the point of this call.

### -s, --signal

  Send a signal to the master process.

  The arguments signal can be on of: **stop, quit, reload**.

  The following table shows the corresponding system signals:

  ARG    | SIGNAL
  -------|---------
  stop   | SIGTERM
  quit   | SIGQUIT
  reload | SIGHUP

### -p, --prefix

  Set the prefix path.

  The default value is a directory `package.json` exists.

### -c, --config

  Use an alternative configuration file.

### -g, --directives

  Override or set global configuration directives.

  JavaScript object format acceptable. (e.g. `-g "{pid: './tmp/em2.pid'}"`)


# signals

  The master process of **ema** can handle the following signals:

  SIGNAL           | operation
  -----------------|--------------
  SIGINT, SIGTERM  | Shut down quickly.
  SIGQUIT          | Shut down gracefully.
  SIGHUP           | Reload configuration, start the new worker process with a new configuration, and gracefully shut down old worker processes.


# configuration

  configuration file example.
  **ema** supports [json5](https://github.com/aseemk/json5).

```
{                                       // global directive
  name       : 'myapp'
  pid_path   : '%h/.myapp.pid',
  access_log : 'log/access.%t.%n.log',
  error_log  : 'log/error.%t.%n.log',
  clustering : 2,
  server: {                             // server directive
    dev: {
      script      : 'config/app.coffee',
      clustering  : 'inherit',
      unmatch_env : 'production',
      env: {
        PORT: 3000
      }
    },
    web: {
      script      : 'config/app.coffee',
      clustering  : 'auto',
      unmatch_env : 'development',
      env: {
        PORT: 3030
      }
    },
    test: {
      script      : 'tests/test.coffee',
      match_env   : 'test'
    }
  }
}
```

this configuration file wakes following named processes:

```
$ ema -d
$ ps ax | grep -v grep | grep myapp:
10000 s002  S+     0:00.12 myapp:master 
10001 s002  S+     0:00.41 myapp:worker:dev.1 
10002 s002  S+     0:00.41 myapp:worker:dev.2
$ ls -a ~ | grep .pid
.myapp.pid
```

with production (4 core cpu):

```
$ NODE_ENV=production ema -d
$ ps ax | grep -v grep | grep myapp:
10000 s002  S+     0:00.12 myapp:master 
10001 s002  S+     0:00.41 myapp:worker:web.1 
10002 s002  S+     0:00.41 myapp:worker:web.2 
10003 s002  S+     0:00.41 myapp:worker:web.3 
10004 s002  S+     0:00.41 myapp:worker:web.4 
```


## configuration keys

### common directive

key          | description                       | defaults
-------------|-----------------------------------|-----------
`access_log` | access log path.                  | `String '%d/tmp/log/access.log'`
`error_log`  | error log path.                   | `String '%d/tmp/log/error.log'`
`clustering` | num of clustering.                | ``Number `os.cpus().length` ``

### global directive

key          | description                       | defaults
-------------|-----------------------------------|----------
`name`       | name for your application.        | `String ema`
`pid_path`   | pid path.                         | `String '%d/tmp/ema.pid'`
`interval`   | reload processes interval.        | `Number 500`
`server`     | server directives.                | `Object {}`

### server directive

directive key name set to `process.title`.

key           | description                      | defaults
--------------|----------------------------------|----------
`script`      | main script name.                | `String null`
`match_env`   | starts only it matched to env.   | `String null`
`unmatch_env` | starts only it unmatched to env. | `String null`
`env`         | exports to `process.env`.        | `Object {}`


## conversion specifier

specifier | description         | directive      | e.g.
----------|---------------------|----------------|------
`%h`      | user home directory | global, server | `/home/user`
`%d`      | project root path   | global, server | `/home/user/project`
`%p`      | port number         | global, server | `3000`
`%e`      | node env            | global, server | `development`
`%t`      | process title label | server         | `web`
`%c`      | clustered order     | server         | `/[0-3]/`
`%C`      | number of clusters  | server         | `4`

# files

  `${prefix}/tmp/ema.pid`

  Contains the process ID of **ema**. The contents of this file are not sensitive, so it can be world-readable.

  `${prefix}/Emafile{,.json}`

  The main configuration file. To set alternative, use `[-c filename]` option.

  `${prefix}/tmp/log/access.log`

  Log file. To set alternative, check configuration section.

  `${prefix}/tmp/log/error.log`

  Error log file. To set alternative, check configuration section.


# exit status.

  Exit status is `0` on success, or `1` if the command fails.


# examples

  Test configuration file `$PROJECT/config/process.json` with global directives for PID:

    ema -t -c ./config/process.json -g "{ pid_path: '/tmp/.ema.pid' }"

