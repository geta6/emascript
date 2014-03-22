_ = require 'lodash'
os = require 'os'
fs = require 'fs'
path = require 'path'
JSON5 = require 'json5'
cluster = require 'cluster'
{error, print} = require 'util'


exports.conversion = (str) ->
  return null if _.isNull str
  str = str
    .replace /%h/g, process.env.HOME
    .replace /%d/g, process.cwd()
    .replace /%p/g, process.env.PORT
    .replace /%e/g, process.env.NODE_ENV
  if cluster.isWorker
    str = str
      .replace /%t/g, process.env.EMA_TITLE
      .replace /%c/g, process.env.EMA_CLUSTER
      .replace /%C/g, process.env.EMA_CLUSTERS
  return str
    .replace /%%/g, '%'
    .replace /%[a-z]/gi, ''


exports.descendant = (obj, desc) ->
  # a = b: c: 4
  # `__descendant a, 'b.c'` returns 4
  descs = desc.split '.'
  continue while descs.length and descs.length and obj = obj[descs.shift()]
  return obj


exports.safeforlog = (dst, options = {}) ->
  return yes if options.allowNull and dst is null
  return no if (fs.existsSync dst) and (fs.statSync dst).isDirectory()
  return no if (fs.existsSync path.dirname dst) and (fs.statSync path.dirname dst).isFile()
  return yes


exports.configuration = (program, defaults) ->
  try

    if _.isString program.directives
      program.directives = program.directives.trim()
      program.directives = "{#{program.directives}" unless /^{/.test program.directives
      program.directives = "#{program.directives}}" unless /}$/.test program.directives
      program.directives = _.defaults (JSON5.parse program.directives), defaults.global

    verbose = program.test and not program.quiet

    for ext in [ '', '.json', '.json5', null ]
      if _.isNull ext
        error "configuration file '#{program.config}' not found."
        process.exit 1
      if fs.existsSync config = path.resolve program.config + ext
        directives = _.extend program.directives, JSON5.parse fs.readFileSync config, 'utf-8'
        program.directives = _.pick directives, [
          'name', 'pid_path', 'access_log', 'error_log', 'clustering', 'timeout', 'server'
        ]
        program.directives.pid_path = exports.conversion program.directives.pid_path
        unless exports.safeforlog program.directives.pid_path, { allowNull: no }
          throw new Error "'pid_path' should be writeable path"
        else if verbose
          print "✓ 'pid_path' is valid [#{program.directives.pid_path}]\n"
        if program.directives.access_log
          program.directives.access_log = exports.conversion program.directives.access_log
          unless exports.safeforlog program.directives.access_log, { allowNull: yes }
            throw new Error "'access_log' should be writeable path"
          else if verbose
            print "✓ 'access_log' is valid [#{program.directives.access_log}]\n"
        if program.directives.error_log
          program.directives.error_log = exports.conversion program.directives.error_log
          unless exports.safeforlog program.directives.error_log, { allowNull: yes }
            throw new Error "'error_log' should be writeable path"
          else if verbose
            print "✓ 'error_log' is valid [#{program.directives.error_log}]\n"
        if program.directives.clustering is 'auto'
          program.directives.clustering = os.cpus().length
        else
          program.directives.clustering = parseInt program.directives.clustering, 10
        unless _.isNumber program.directives.clustering
          throw new Error "'clustering' should be a number"
        else if verbose
          print "✓ 'clustering' is valid [#{program.directives.clustering}]\n"
        unless _.isNumber program.directives.timeout
          throw new Error "'timeout' should be a number"
        else if verbose
          print "✓ 'timeout' is valid [#{program.directives.timeout}]\n"
        unless (_.isObject program.directives.server) and 0 < (_.keys program.directives.server).length
          throw new Error "'server' should be valid object\n"
        else if verbose
          print "✓ 'server' is valid object [{#{_.keys(program.directives.server).join ','}}]\n"
        break

    for title, config of program.directives.server
      program.directives.server[title] = _.defaults program.directives.server[title], defaults.server
      program.directives.server[title] = _.pick program.directives.server[title], [
        'access_log', 'error_log', 'clustering', 'script', 'match_env', 'unmatch_env', 'env'
      ]
      if _.isNull program.directives.server[title].script
        throw new Error "'server.#{title}.script' should be file"
      program.directives.server[title].script = path.resolve program.directives.server[title].script
      unless fs.existsSync program.directives.server[title].script
        throw new Error "'server.#{title}.script' should be exists"
      else if verbose
        print "✓ 'server.#{title}.script' exists [#{program.directives.server[title].script}]\n"
      access_log_inherit = no
      if program.directives.server[title].access_log in [ null, 'inherit' ]
        access_log_inherit = yes
        program.directives.server[title].access_log = program.directives.access_log
      error_log_inherit = no
      if program.directives.server[title].error_log in [ null, 'inherit' ]
        error_log_inherit = yes
        program.directives.server[title].error_log = program.directives.error_log
      clustering_inherit = no
      if program.directives.server[title].clustering in [ 'auto', 'inherit' ]
        clustering_inherit = yes
        program.directives.server[title].clustering = program.directives.clustering
      unless _.isNumber program.directives.server[title].clustering
        throw new Error "'server.#{title}.clustering' should be a number"
      else if verbose
        print "✓ 'server.#{title}.clustering' is valid [#{program.directives.server[title].clustering}#{if clustering_inherit then ' (inherit)'}]\n"
      if _.isString program.directives.server[title].match_env
        try
          if program.directives.server[title].match_env
            program.directives.server[title].match_env = new RegExp program.directives.server[title].match_env
        catch err
          throw new Error "'server.#{title}.match_env' should be valid regular expression"
        if verbose
          print "✓ 'server.#{title}.match_env' is valid [#{program.directives.server[title].match_env}]\n"
      if _.isString program.directives.server[title].unmatch_env
        try
          if program.directives.server[title].unmatch_env
            program.directives.server[title].unmatch_env = new RegExp program.directives.server[title].unmatch_env
        catch err
          throw new Error "'server.#{title}.unmatch_env' should be valid regular expression"
        if verbose
          print "✓ 'server.#{title}.unmatch_env' is valid [#{program.directives.server[title].unmatch_env}]\n"
      unless _.isObject program.directives.server[title].env
        throw new Error "'server'.#{title}.env' should be object"

  catch err
    error "! #{err.message}"
    error "configuration file '#{program.config}' test is failed"
    process.exit 1

  if program.test
    print "configuration file '#{program.config}' test is successful\n"
    process.exit 0

  return program



