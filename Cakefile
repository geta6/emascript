{print, error} = require 'util'
{spawn} = require 'child_process'

option '-w', '--watch', 'Recompile CoffeeScript source file when modified'

task 'build', 'Build all scripts', (options) ->

  opt = [ '-bco', 'lib', 'src' ]
  opt.unshift '-w' if options.watch

  coffee = spawn './node_modules/.bin/coffee', opt
  coffee.stdout.on 'data', print
  coffee.stderr.on 'data', error

