
ChatServiceError = require './ChatServiceError'
Promise = require 'bluebird'
_ = require 'lodash'

# Transport public API interface. An instance of {Transport}
# implementation is available in a {ChatService} instance.
class Transport

  # Sends a message to a channel (each room has a channels with the
  # same name).
  #
  # @param channel [String] A channel.
  # @param messageName [String] Message name.
  # @param messageData [Array] Message data.
  #
  # @return [null]
  emitToChannel : (channel, messageName, messageData...) ->

  # Sends a message to a channel (each room has a channels with the
  # same name), excluding the sender socket.
  #
  # @param id [String] Sender socket id.
  # @param channel [String] A channel.
  # @param messageName [String] Message name.
  # @param messageData [Array] Message data.
  #
  # @return [null]
  sendToChannel : (id, channel, messageName, messageData...) ->

module.exports = Transport
