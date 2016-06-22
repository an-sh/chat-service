
EventEmitter = require('events').EventEmitter

# ChatService lifecycle events.
class ChatServiceEvents extends EventEmitter

  # @event ready Service is ready.
  # @event closed
  #   Service is closed.
  #   @param [Error or undefined] error Non-null if closed due to an error.
  constructor : ->
    super


module.exports = ChatServiceEvents
