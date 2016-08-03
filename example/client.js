
let io = require('socket.io-client')
let url = 'ws://localhost:8000/chat-service'
let userName = `user${Math.floor(Math.random() * 99) + 1}`
let token = 'token' // auth token
let query = `userName=${userName}&token=${token}`
let params = { query }
// Connect to server.
let socket = io.connect(url, params)
socket.once('loginConfirmed', (userName) => {
  // Auth success.
  socket.on('roomMessage', (room, msg) => {
    // Rooms messages handler (own messages are here too).
    console.log(`${msg.author}: ${msg.textMessage}`)
  })
  // Join room 'default'.
  socket.emit('roomJoin', 'default', (error, data) => {
    // Check for a command error.
    if (error) return
    // Now we will receive 'default' room messages in 'roomMessage' handler.
    // Now we can also send a message to 'default' room:
    socket.emit('roomMessage', 'default', { textMessage: 'Hello!' })
  })
})
socket.once('loginRejected', (error) => {
  // Auth error handler.
  console.error(error)
})
