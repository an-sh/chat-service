
del = require 'del'
gulp = require 'gulp'
path = require 'path'

cwdj = (dir) -> path.join __dirname, dir

chatConfig =
  jsOutput : cwdj '/build/public/javascripts'
  jsOutputDev : cwdj '/build/public-dev/javascripts'
  cssOutput : cwdj '/build/public/stylesheets'
  cssOutputDev : cwdj '/build/public-dev/stylesheets'
  partialsOutputDev : cwdj '/build/public-dev/partials'

(require cwdj '/client/chat-frontend/gulpfile.coffee') gulp, chatConfig

server = cwdj '/server/'
serverFiles = cwdj '/server/**/*'
clientDeps = cwdj 'client/dependencies.jade'
buildDir = cwdj '/build/'
depsDir = cwdj '/build/views'

gulp.task 'client-dependencies', ->
  gulp.src clientDeps
    .pipe gulp.dest depsDir

gulp.task 'client-dependencies-watch', ['client-dependencies'], ->
  gulp.watch clientDeps, ['client-dependencies']

gulp.task 'server', ->
  gulp.src(serverFiles, base: server)
    .pipe gulp.dest buildDir

gulp.task 'server-watch', ['server'], ->
  gulp.watch serverFiles, ['server']

gulp.task 'clean', ->
  del [ buildDir ]

gulp.task 'default', ['server', 'client-dependencies', 'chat', 'chat-dev']

gulp.task 'watch', ['server-watch', 'client-dependencies-watch', 'chat-watch']
