
Promise = require 'bluebird'
User = require './User.coffee'
_ = require 'lodash'


# @mixin
# TODO API for a service maintenance.
MaintenanceAPI =

  # TODO
  # roomUserlistSync : (roomName, userName = null) ->

  # TODO
  # userSocketsSync : (userName, socket = null) ->

  # Fix instance data after a crash.
  #
  # @param id [String] Instance id.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  instanceRecover : (id, cb) ->
    @state.getInstanceSockets id
    .then (sockets) =>
      Promise.each _.toPairs(sockets), ([id, userName]) =>
        @execUserCommand {userName, id}, 'disconnect', 'instance recovery'
    .asCallback cb


module.exports = MaintenanceAPI
