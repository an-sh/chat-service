
const io = require('socket.io-client')

// Use https or wss in production.
const url = 'ws://localhost:8000/chat-service'
const userName = `user${Math.floor(Math.random() * 99) + 1}`
const token = 'token' // auth token
const query = `userName=${userName}&token=${token}`
const opts = { query }

// Connect to a server.
const socket = io.connect(url, opts)

// Rooms messages handler (own messages are here too).
socket.on('roomMessage', (room, msg) => {
  console.log(`${msg.author}: ${msg.textMessage}`)
})

// Auth success handler.
socket.on('loginConfirmed', userName => {
  // Join room named 'default'.
  socket.emit('roomJoin', 'default', (error, data) => {
    // Check for a command error.
    if (error) { return }
    // Now we will receive 'default' room messages in 'roomMessage' handler.
    // Now we can also send a message to 'default' room:
    socket.emit('roomMessage', 'default', { textMessage: 'Hello!' })
  })
})

// Auth error handler.
socket.on('loginRejected', error => {
  console.error(error)
})
