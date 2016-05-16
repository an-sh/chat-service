
path = require 'path'
express = require 'express'
http = require 'http'
ChatService = require('../../index.js')
Room = require('../../index.js').Room

app = express()
views = path.join __dirname, '/views'

if app.get('env') == 'development'
  app.locals.pretty = true
  resources = path.join __dirname, '/public-dev'
  livereload = (require 'livereload').createServer(exts : ['jade'])
  livereload.watch [resources, views]
else
  resources = path.join __dirname, '/public'


auth = (data, next) ->
  unless data.handshake.query?.user
    next new Error 'No login data.'
  else
    next()


server = require('http').Server app
chat = new ChatService { enableUserlistUpdates : true }, { auth }
chat.addRoom 'default', { adminlist: ['admin'], owner : 'admin' }
.catch (e) ->
  console.error e

app.set 'views', views
app.set 'view engine', 'jade'

router = express.Router()
app.use '/', router
app.use express.static resources

router.get '/', (req, res) ->
  res.render 'index'

module.exports = server
