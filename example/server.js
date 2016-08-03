
function onConnect (service, id) {
  // Assuming that auth data is passed in a query string.
  let { query } = service.transport.getHandshakeData(id)
  let { userName } = query
  // Actually check auth data.
  // ...
  // Return a promise that resolves with a login string.
  return Promise.resolve(userName)
}

const port = 8000
const ChatService = require('../index')
const chatService = new ChatService({port}, {onConnect})
process.on('SIGINT', () => chatService.close().finally(() => process.exit()))

chatService.addRoom('default', { owner: 'admin' })
