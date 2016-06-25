
_ = require 'lodash'
config = require './config.coffee'
testutils = require './testutils.coffee'


before testutils.checkDB

describe 'Chat service.', ->

  _.forEach config.states, (state) ->

    describe "State: '#{state.state}', adapter: '#{state.adapter}'.", ->

      before -> testutils.setState state

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

      describe 'Validation', require './validation.coffee'

      describe 'Errors handling', require './errorsHandling.coffee'

  describe 'Node cluster communication', require './nodeCluster.coffee'

  describe 'Consistency failures', require './consistencyFailures.coffee'
