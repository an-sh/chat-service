
Promise = require 'bluebird'
_ = require 'lodash'


# @mixin
# API for service maintenance.
MaintenanceAPI =

  # TODO
  roomUserlistSync : (roomName, userName = null) ->

  # TODO
  userSocketsSync : (userName, socket = null) ->

  # TODO
  instanceRecover : (id) ->

  # TODO
  getInstanceHeartbeat : (id) ->



module.exports = MaintenanceAPI
