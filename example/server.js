
const ChatService = require('../index')

const port = 8000

function onConnect (service, id) {
  // Assuming that auth data is passed in a query string.
  let { query } = service.transport.getHandshakeData(id)
  let { userName } = query
  // Actually check auth data.
  // ...
  // Return a promise that resolves with a login string.
  return Promise.resolve(userName)
}

const chatService = new ChatService({port}, {onConnect})

process.on('SIGINT', () => chatService.close().finally(() => process.exit()))

// It is an error to add the same room twice. The room configuration
// and messages will persist if redis state is used.
chatService.hasRoom('default').then(hasRoom => {
  if (!hasRoom) {
    return chatService.addRoom('default', { owner: 'admin' })
  }
})
