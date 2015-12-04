
browserify = require 'browserify'
buffer = require 'vinyl-buffer'
coffee = require 'gulp-coffee'
coffeeify = require 'coffeeify'
concat = require 'gulp-concat'
jade = require 'gulp-jade'
minifyCss = require 'gulp-minify-css'
ngannotate = require 'browserify-ngannotate'
path = require 'path'
source = require 'vinyl-source-stream'
sourcemaps = require 'gulp-sourcemaps'
streamqueue = require 'streamqueue'
stylus = require 'gulp-stylus'
templateCache = require 'gulp-angular-templatecache'
uglifyify = require 'uglifyify'

codeDir = path.join(__dirname, '/angular/')
code = codeDir + '*.coffee'
partials = path.join(__dirname, '/partials/') + '*.jade'
css = path.join(__dirname, '/stylus/') + '*.styl'
app = codeDir + 'app.coffee'

setTasks = ->

  gulp.task 'chat-js', ->
    streamqueue { objectMode : true },
      browserify { debug : false }
        .transform coffeeify
        .transform { ext: '.coffee' }, ngannotate
        .transform { global: true }, uglifyify
        .add app
        .bundle()
        .pipe source 'fake.js'
        .pipe buffer()
      gulp.src partials
        .pipe jade()
        .pipe templateCache { root : 'partials/'
          , module : 'chatTemplates'
          , moduleSystem : 'IIFE' }
    .pipe concat 'chat.js'
    .pipe gulp.dest argv.jsOutput

  gulp.task 'chat-js-dev', ->
    browserify { debug : true }
      .transform coffeeify
      .add app
      .bundle()
      .pipe source 'chat.js'
      .pipe gulp.dest argv.jsOutputDev

  gulp.task 'chat-css', ->
    gulp.src css
      .pipe stylus()
      .pipe minifyCss()
      .pipe gulp.dest argv.cssOutput

  gulp.task 'chat-css-dev', ->
    gulp.src css
      .pipe sourcemaps.init()
      .pipe stylus()
      .pipe sourcemaps.write()
      .pipe gulp.dest argv.cssOutputDev

  gulp.task 'chat-partials-dev', ->
    gulp.src partials
      .pipe jade {pretty : true}
      .pipe gulp.dest argv.partialsOutputDev

  gulp.task 'chat', ['chat-js', 'chat-css' ]

  gulp.task 'chat-dev', ['chat-js-dev', 'chat-css-dev', 'chat-partials-dev' ]

  gulp.task 'chat-watch', ['chat', 'chat-dev'], ->
    gulp.watch code, ['chat-js', 'chat-js-dev']
    gulp.watch css, ['chat-css', 'chat-css-dev']
    gulp.watch partials, ['chat-js', 'chat-partials-dev']


if !module.parent?.parent
  gulp = require 'gulp'
  argv = require('yargs')
    .usage('Chat build parameters')
    .describe('js-output', 'Angular output file path')
    .describe('css-output', 'CSS output file path')
    .describe('js-output-dev', 'Angular development output file path')
    .describe('css-output-dev', 'CSS development output file path')
    .describe('partials-output-dev', 'Partials development output file path')
    .argv
  setTasks()
  gulp.task 'default', ['chat', 'chat-dev']


module.exports = (g, opts) ->
  gulp = g
  argv = opts
  setTasks()
  return
