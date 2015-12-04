
path = require 'path'
express = require 'express'
http = require 'http'
ChatServer = require('../../index.js').ChatService
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


chatOptions = { enableUserlistUpdates : true }
auth = (data, next) ->
  unless data.handshake.query?.user
    next new Error 'No login data.'
  else
    next()

server = require('http').Server app
chat = new ChatServer chatOptions, {auth : auth}
defaultRoom = new Room chat, 'default'
admin = 'admin'
chat.chatState.addRoom defaultRoom, ->
  defaultRoom.roomState.ownerSet admin, ->
    defaultRoom.roomState.addToList 'adminlist', [admin], ->

app.set 'views', views
app.set 'view engine', 'jade'

router = express.Router()
app.use '/', router
app.use express.static resources

router.get '/', (req, res) ->
  res.render 'index'

module.exports = server
