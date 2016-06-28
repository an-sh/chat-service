
Promise = require 'bluebird'
User = require './User'
_ = require 'lodash'


# @mixin
# API for a service state recovery.
RecoveryAPI =

  # Fix user state user association. (TODO)
  #
  # @param userName [String] Username.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  userStateSync : (userName) ->

  # Fix instance data after an incorrect service shutdown.
  #
  # @param id [String] Instance id.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  instanceRecovery : (id, cb) ->
    @state.getInstanceSockets id
    .then (sockets) =>
      Promise.each _.toPairs(sockets), ([id, userName]) =>
        @execUserCommand {userName, id}, 'disconnect', 'instance recovery'
    .asCallback cb


module.exports = RecoveryAPI
