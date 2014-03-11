###
# ema - node.js supervisor script.
###

# dependencies

require 'coffee-script/register'
_ = require 'lodash'
fs = require 'fs'
path = require 'path'
async = require 'async'
mkdirp = require 'mkdirp'
helper = require './helper'
cluster = require 'cluster'


if cluster.isMaster

  # master

  program = require 'commander'
  {spawn} = require 'child_process'
  {error} = require 'util'


  # parse arguments

  loop
    break if fs.existsSync path.resolve 'package.json'
    if process.cwd() is '/'
      error "project definition file 'package.json' not found."
      process.exit 1
    process.chdir '../'

  pkg = require path.resolve 'package.json'
  ema = require path.join (path.dirname path.dirname process.mainModule.filename), 'package.json'

  defaults =
    global:
      name: 'ema'
      pid_path: '%d/tmp/ema.pid'
      access_log: '%d/tmp/log/access.log'
      error_log: '%d/tmp/log/error.log'
      clustering: 'auto'
      timeout: 2400
      server: {}
    server:
      access_log: null
      error_log: null
      clustering: 'inherit'
      script: pkg.main || null
      match_env: null
      unmatch_env: null
      env: {}

  program
    .usage '[-hVtqd] [-s signal] [-p dirname] [-c filename] [-g directives]'
    .version ema.version
    .option '-t, --test', 'test configuration and exit'
    .option '-q, --quiet', 'suppress non-error messages during configuration testing'
    .option '-d, --daemon', 'daemonize process'
    .option '-s, --signal <signal>', 'send signal to a master process: stop, quit, reload'
    .option '-p, --prefix <dirname>', 'set prefix path', path.resolve()
    .option '-c, --config <filename>', 'set JSON5 configuration file', 'Emafile'
    .option '-g, --directives <directive>', 'set master directives out of configuration file', _.clone defaults.global
    .parse process.argv


  # parse and test directives from config

  program = helper.configuration program, defaults

  if program.prefix
    process.chdir program.prefix


  # signal

  if program.signal
    try
      pid = parseInt (fs.readFileSync program.directives.pid_path, 'utf-8'), 10
      switch program.signal
        when 'stop'
          process.kill pid, 'SIGTERM'
        when 'quit'
          process.kill pid, 'SIGQUIT'
        when 'reopen'
          process.kill pid, 'SIGUSR1'
        when 'reload'
          process.kill pid, 'SIGHUP'
        else
          throw new Error 'signal should be stop, quit, reopen or reload'
      process.exit 0

    catch err
      error "! #{err.message}"
      error "signal operation '#{program.signal}' failed"
      process.exit 1


  # prevents

  try
    if fs.existsSync program.directives.pid_path
      pid = parseInt (fs.readFileSync program.directives.pid_path, 'utf-8'), 10
      try
        process.kill pid, 'SIGCONT'
        error "! #{program.directives.name} already booted."
        process.exit 1
  catch err
    fs.unlinkSync program.directives.pid_path
    error "! ##{pid} already dead, clear pid_path"


  # daemon

  if program.daemon and not process.env.__daemon
    args = [].concat process.argv
    args.shift()
    script = args.shift()
    process.env.__daemon = yes
    child = spawn process.execPath, [script].concat(args),
      stdio: [ 'ignore', 'ignore', 'ignore' ]
      env: process.env
      cwd: process.cwd()
      detached: yes
    child.unref()
    process.exit 0


  # wakeup apps

  unless fs.existsSync path.dirname program.directives.pid_path
    mkdirp.sync path.dirname program.directives.pid_path
  fs.writeFile program.directives.pid_path, process.pid, (err) ->
    if err
      error err.stack || err.message
      process.exit 1

    process.title = "#{program.directives.name}:master"

    workers = {}

    # signal listener

    process.on 'SIGHUP', ->
      error 'Reload all processes.'
      async.eachSeries (_.keys workers), (uid, next) ->
        worker = workers[uid]
        setImmediate ->
          timeout = setTimeout ->
            worker.kill 'SIGTERM'
            return next null
          , program.directives.timeout
          worker.disconnect ->
            clearTimeout timeout
            return next null
      , ->
        error 'Reload done.'

    process.on 'SIGQUIT', ->
      cluster.removeAllListeners 'exit'
      async.each (_.keys workers), (uid, next) ->
        worker = workers[uid]
        setImmediate ->
          timeout = setTimeout ->
            worker.kill 'SIGTERM'
            return next null
          , program.directives.timeout
          worker.disconnect ->
            clearTimeout timeout
            return next null
      , ->
        fs.unlinkSync program.directives.pid_path
        process.exit 0


    # fail listener

    cluster.on 'exit', (worker) ->
      delete workers[worker.uid]
      config = JSON.parse worker.config
      worker = cluster.fork config.env
      worker.uid = _.uniqueId()
      worker.config = JSON.stringify config
      workers[worker.uid] = worker


    # start

    unless process.env.NODE_ENV
      process.env.NODE_ENV = 'development'

    for title, config of program.directives.server
      if not (_.isRegExp config.match_env) or config.match_env.test process.env.NODE_ENV
        if not (_.isRegExp config.unmatch_env) or not config.unmatch_env.test process.env.NODE_ENV
          for index in [1..config.clustering]
            config.env = _.extend (_.clone config.env),
              EMA_NAME: program.directives.name
              EMA_TITLE: title
              EMA_CLUSTER: index
              EMA_CLUSTERS: config.clustering
              EMA_PREFIX: program.prefix
              EMA_SCRIPT: config.script
              EMA_STDOUT: config.access_log
              EMA_STDERR: config.error_log
            worker = cluster.fork config.env
            worker.uid = _.uniqueId()
            worker.config = JSON.stringify config
            workers[worker.uid] = worker


else

  # worker

  {inspect} = require 'util'

  unless process.env.NODE_ENV
    process.env.NODE_ENV = 'development'

  colors = parseInt process.env.EMA_CLUSTER, 10
  colors = [6, 2, 3, 4, 5, 1][colors % 6]

  coerce = (val) ->
    return (val.stack or val.message) if val instanceof Error
    return val if 'object' isnt typeof val
    return inspect val

  logger = (write, dst) -> ->
    date = (d) ->
      mo = ('00' + (1 + d.getMonth())).slice -2
      da = ('00' + d.getDate()).slice -2
      ho = ('00' + d.getHours()).slice -2
      mi = ('00' + d.getMinutes()).slice -2
      se = ('00' + d.getSeconds()).slice -2
      return "#{mo}/#{da} #{ho}:#{mi}:#{se}"
    args = (_.map (Array::slice.call arguments), coerce).join ''
    args += '\n' unless /[\n\r]$/.test args
    now = new Date
    fs.appendFile dst, "#{date now} #{args}" if dst
    write.call @, "\u001b[9#{colors}m#{date now} worker:#{process.env.EMA_TITLE}.#{process.env.EMA_CLUSTER}  \u001b[90m#{args}\u001b[0m"

  process.chdir process.env.EMA_PREFIX

  process.title = "#{process.env.EMA_NAME}:worker:#{process.env.EMA_TITLE}.#{process.env.EMA_CLUSTER}"
  process.env.EMA_STDOUT = helper.conversion process.env.EMA_STDOUT
  process.env.EMA_STDERR = helper.conversion process.env.EMA_STDERR
  process.env.EMA_SCRIPT = helper.conversion process.env.EMA_SCRIPT

  unless _.isNull process.env.EMA_STDOUT = helper.conversion process.env.EMA_STDOUT
    mkdirp.sync path.dirname process.env.EMA_STDOUT
  process.stdout.write = logger process.stdout.write, process.env.EMA_STDOUT

  unless _.isNull process.env.EMA_STDERR = helper.conversion process.env.EMA_STDERR
    mkdirp.sync path.dirname process.env.EMA_STDERR
  process.stderr.write = logger process.stderr.write, process.env.EMA_STDERR

  delete require.cache[process.env.EMA_SCRIPT] if require.cache[process.env.EMA_SCRIPT]?
  require process.env.EMA_SCRIPT

