
testutils = require './testutils.coffee'
config = require './config.coffee'


before testutils.checkDB

describe 'Chat service.', ->

  for state in config.states

    testutils.setState state

    describe "State: #{state.state}, Adapter: #{state.adapter}.", ->

      describe 'Initialization', require './initialization.coffee'

      describe 'Connection', require './connection.coffee'

      describe 'Room management', require './roomManagement.coffee'

      describe 'Room messaging', require './roomMessaging.coffee'

      describe 'Room permissions', require './roomPermissions.coffee'

      describe 'Direct messaging', require './directMessaging.coffee'

      describe 'Direct permissions', require './directPermissions.coffee'

      describe 'Hooks', require './hooks.coffee'

      describe 'API', require './api.coffee'

      describe 'API permissions', require './apiPermissions.coffee'

      describe 'Validation and errors', require './validation.coffee'
