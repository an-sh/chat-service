
ChatServiceError = require './ChatServiceError'
Promise = require 'bluebird'
_ = require 'lodash'

# Transport public API interface. An instance of {Transport}
# implementation is available as a member of {ChatService} instance.
class Transport

  # Sends a message to a channel (each room has a channel with the
  # same name). This messages are sent directly, bypassing room
  # history and permissions.
  #
  # @param channel [String] A channel.
  # @param messageName [String] Message name.
  # @param messageData [Rest...] Message data.
  #
  # @return [null]
  emitToChannel : (channel, messageName, messageData...) ->

  # Sends a message to a channel (each room has a channel with the
  # same name), excluding the sender socket. This messages are sent
  # directly, bypassing room history and permissions.
  #
  # @param id [String] Sender socket id.
  # @param channel [String] A channel.
  # @param messageName [String] Message name.
  # @param messageData [Rest...] Message data.
  #
  # @return [null]
  sendToChannel : (id, channel, messageName, messageData...) ->

  # Get an underlying connection object by id.
  #
  # @param id [String] Socket id.
  #
  # @return [Object or null] Connection object corresponding to the
  #   socket id. Returns `null` if the connection was closed.
  getConnectionObject : (id) ->


module.exports = Transport
